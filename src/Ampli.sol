// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import {mulDiv, mulDiv18, sqrt} from "prb-math/Common.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {IAmpli} from "src/interfaces/IAmpli.sol";
import {IUnlockCallback} from "src/interfaces/callbacks/IUnlockCallback.sol";
import {BaseHook, IPoolManager, Hooks, PoolKey, BalanceDelta} from "src/modules/externals/BaseHook.sol";
import {FungibleToken} from "src/modules/FungibleToken.sol";
import {NonFungibleTokenReceiver} from "src/modules/NonFungibleTokenReceiver.sol";
import {RiskConfigs, IRiskGovernor} from "src/modules/RiskConfigs.sol";
import {Deflators} from "src/structs/Deflators.sol";
import {ExchangeRate} from "src/structs/ExchangeRate.sol";
import {Lock} from "src/structs/Lock.sol";
import {Position} from "src/structs/Position.sol";
import {Fungible, FungibleLibrary} from "src/types/Fungible.sol";
import {NonFungible, NonFungibleLibrary} from "src/types/NonFungible.sol";
import {Constants} from "src/utils/Constants.sol";

/// @notice The Ampli protocol contract
contract Ampli is IAmpli, BaseHook, FungibleToken, NonFungibleTokenReceiver, RiskConfigs {
    struct ConstructorArgs {
        IPoolManager poolManager;
        uint24 poolSwapFee;
        int24 poolTickSpacing;
        string tokenName;
        string tokenSymbol;
        uint8 tokenDecimals;
        IRiskGovernor riskGovernor;
        RiskParams riskParams;
    }

    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    /// @notice Throws if the function is called via a delegate call
    error NoDelegateCall();

    uint256 private constant GLOBAL_POSITION_ID = 0;
    address private immutable s_self;
    PoolKey private s_poolKey;

    Lock internal s_lock;
    Deflators private s_deflators;
    ExchangeRate private s_exchangeRate;

    uint256 private s_deficit;
    uint256 private s_surplus;
    uint256 private s_lastPositionId;
    mapping(uint256 => Position) private s_positions;
    mapping(NonFungible => mapping(uint256 => uint256)) private s_nonFungibleItemPositions;

    /// @notice Modifier for functions that cannot be called via a delegate call
    modifier noDelegateCall() {
        if (address(this) != s_self) revert NoDelegateCall();
        _;
    }

    constructor(ConstructorArgs memory args)
        BaseHook(
            args.poolManager,
            Hooks.Permissions(false, false, true, false, true, false, true, true, false, false, false, false, false, false)
        )
        FungibleToken(args.tokenName, args.tokenSymbol, args.tokenDecimals)
        RiskConfigs(args.riskGovernor, args.riskParams)
    {
        s_self = address(this);
        s_poolKey =
            PoolKey(CurrencyLibrary.NATIVE, Currency.wrap(address(this)), args.poolSwapFee, args.poolTickSpacing, this);
        s_poolManager.initialize(s_poolKey, Constants.ONE_Q96, "");

        s_deflators.initialize();
        s_exchangeRate.initialize(Constants.ONE_UD18);

        s_positions[GLOBAL_POSITION_ID].open(address(this), address(0));
    }

    /// @inheritdoc IAmpli
    function unlock(bytes calldata callbackData) external returns (bytes memory callbackResult) {
        s_lock.unlock();

        (uint256 sqrtPriceX96,,,) = s_poolManager.getSlot0(s_poolKey.toId());
        _disburseInterest();
        _adjustExchangeRate(sqrtPriceX96, false);

        callbackResult = IUnlockCallback(msg.sender).unlockCallback(callbackData);

        uint256[] memory checkedOutPositions = s_lock.checkedOutItems;
        uint256 len = checkedOutPositions.length;
        for (uint256 i; i < len; ++i) {
            Position storage s_position = s_positions[checkedOutPositions[i]];
            (uint256 value, uint256 marginReq) =
                s_position.appraise(this, Fungible.wrap(address(this)), s_exchangeRate.currentUD18);
            uint256 debt = s_position.nominalDebt(s_deflators.interestAndFeeUD18);

            if (value < marginReq + debt || debt > mulDiv18(value, maxDebtRatio())) {
                revert PositionAtRisk(checkedOutPositions[i]);
            }
        }

        s_lock.checkInAll();

        s_lock.lock();
    }

    /// @inheritdoc IAmpli
    function openPosition(address originator) external noDelegateCall returns (uint256 positionId) {
        s_positions[(positionId = ++s_lastPositionId)].open(msg.sender, originator);

        emit PositionOpened(positionId, msg.sender, originator);
    }

    /// @inheritdoc IAmpli
    function closePosition(uint256 positionId) external noDelegateCall {
        if (msg.sender != s_positions[positionId].owner) revert NotOwner();

        s_positions[positionId].close();

        emit PositionClosed(positionId);
    }

    /// @inheritdoc IAmpli
    function depositFungible(uint256 positionId, Fungible fungible, uint256 amount) external payable noDelegateCall {
        if (!s_positions[positionId].exists()) revert PositionDoesNotExist();

        _addFungible(positionId, fungible, amount);

        emit FungibleDeposited(positionId, msg.sender, fungible, amount);
    }

    /// @inheritdoc IAmpli
    function withdrawFungible(uint256 positionId, Fungible fungible, uint256 amount, address recipient)
        external
        noDelegateCall
    {
        if (msg.sender != s_positions[positionId].owner) revert NotOwner();
        s_lock.checkOut(positionId);

        _removeFungible(positionId, fungible, amount);
        fungible.transfer(recipient, amount);

        emit FungibleWithdrawn(positionId, recipient, fungible, amount);
    }

    /// @inheritdoc IAmpli
    function depositNonFungible(uint256 positionId, NonFungible nonFungible, uint256 item) external noDelegateCall {
        if (!s_positions[positionId].exists()) revert PositionDoesNotExist();
        if (nonFungible.ownerOf(item) != address(this)) revert NonFungibleItemNotRecieved();
        if (s_nonFungibleItemPositions[nonFungible][item] != 0) revert NonFungibleItemAlreadyDeposited();

        s_positions[positionId].addNonFungible(nonFungible, item);
        s_positions[GLOBAL_POSITION_ID].addNonFungible(nonFungible, item);
        s_nonFungibleItemPositions[nonFungible][item] = positionId;

        emit NonFungibleDeposited(positionId, msg.sender, nonFungible, item);
    }

    /// @inheritdoc IAmpli
    function withdrawNonFungible(uint256 positionId, NonFungible nonFungible, uint256 item, address recipient)
        external
        noDelegateCall
    {
        if (msg.sender != s_positions[positionId].owner) revert NotOwner();
        if (s_nonFungibleItemPositions[nonFungible][item] != positionId) revert NonFungibleItemNotInPosition();
        s_lock.checkOut(positionId);

        s_positions[positionId].removeNonFungible(nonFungible, item);
        s_positions[GLOBAL_POSITION_ID].removeNonFungible(nonFungible, item);
        delete s_nonFungibleItemPositions[nonFungible][item];
        nonFungible.transfer(recipient, item);

        emit NonFungibleWithdrawn(positionId, recipient, nonFungible, item);
    }

    /// @inheritdoc IAmpli
    function borrow(uint256 positionId, uint256 amount, address recipient) external noDelegateCall {
        if (msg.sender != s_positions[positionId].owner) revert NotOwner();
        s_lock.checkOut(positionId);

        _mint(recipient, amount);
        uint256 realAmount = mulDiv(amount, Constants.ONE_UD18, s_deflators.interestAndFeeUD18) + 1; // lazy rounding up
        s_positions[GLOBAL_POSITION_ID].realDebt += realAmount; // overflow protection
        unchecked {
            s_positions[positionId].realDebt += realAmount;
        }

        if (recipient == address(this)) {
            _addFungible(positionId, Fungible.wrap(address(this)), amount);
        }

        emit Borrow(positionId, recipient, amount, realAmount);
    }

    /// @inheritdoc IAmpli
    function repay(uint256 positionId, uint256 amount) external noDelegateCall {
        if (msg.sender != s_positions[positionId].owner) revert NotOwner();

        _burn(address(this), amount);
        uint256 realAmount = mulDiv(amount, Constants.ONE_UD18, s_deflators.interestAndFeeUD18);
        s_positions[positionId].realDebt -= realAmount;
        unchecked {
            s_positions[GLOBAL_POSITION_ID].realDebt -= realAmount;
        }

        _removeFungible(positionId, Fungible.wrap(address(this)), amount);

        emit Repay(positionId, amount, realAmount);
    }

    /// @inheritdoc IAmpli
    function liquidate(uint256 positionId, address recipient) external noDelegateCall returns (uint256 shortfall) {
        if (!s_positions[positionId].exists()) revert PositionDoesNotExist();
        s_lock.checkOut(positionId);

        (uint256 value, uint256 marginReq) =
            s_positions[positionId].appraise(this, Fungible.wrap(address(this)), s_exchangeRate.currentUD18);
        uint256 debt = s_positions[positionId].nominalDebt(s_deflators.interestAndFeeUD18);
        if (value >= debt + marginReq) revert PositionNotAtRisk();

        // protocol provides relief when position is under water, up to where maxDebtRatio is satisfied
        uint256 relief;
        if (value < debt) {
            relief = mulDiv(debt, Constants.ONE_UD18, maxDebtRatio()) - value;
            s_deficit += relief;
            _mint(address(this), relief);
            _addFungible(positionId, Fungible.wrap(address(this)), relief);
        }

        s_positions[positionId].owner = recipient;
        shortfall = debt + marginReq - (value + relief); // shortfall needs to be provided by the liquidator

        emit Liquidate(positionId, msg.sender, recipient, relief, shortfall);
    }

    /// @inheritdoc IAmpli
    function exchange(address recipient) external payable noDelegateCall {
        uint256 amount = mulDiv(msg.value, s_exchangeRate.currentUD18, Constants.ONE_UD18);

        s_surplus += msg.value;
        _mint(recipient, amount);

        emit Exchange(msg.sender, recipient, msg.value, amount);
    }

    /// @inheritdoc IAmpli
    function settle() external noDelegateCall {
        uint256 deficit_ = s_deficit;

        if (deficit_ > 0) {
            uint256 balance = balanceOf(msg.sender);
            uint256 amount = balance >= deficit_ ? deficit_ : balance; // settle as much as possible

            s_deficit -= amount;
            _burn(msg.sender, amount);

            emit Settle(msg.sender, amount);
        }
    }

    /// @inheritdoc IAmpli
    function collect(address recipient, uint256 amount) external noDelegateCall riskGovernorOnly {
        if (s_deficit == 0) {
            uint256 surplus_ = s_surplus;

            amount = amount == 0 ? surplus_ : amount; // collect as much as possible
            if (surplus_ < amount) revert InsufficientSurplus();

            s_surplus -= amount;
            FungibleLibrary.NATIVE.transfer(recipient, amount);

            emit Collect(recipient, amount);
        }
    }

    /// @inheritdoc BaseHook
    function beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata /*hookData*/
    ) external override noDelegateCall poolManagerOnly returns (bytes4) {
        if (sender != address(this)) {
            (uint256 sqrtPriceX96, int24 tick,,) = s_poolManager.getSlot0(key.toId());

            if (tick >= params.tickLower && tick <= params.tickUpper) {
                _disburseInterest();
            }

            _adjustExchangeRate(sqrtPriceX96, false);
        }

        return this.beforeAddLiquidity.selector;
    }

    /// @inheritdoc BaseHook
    function beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata /*hookData*/
    ) external override noDelegateCall poolManagerOnly returns (bytes4) {
        if (sender != address(this)) {
            (uint256 sqrtPriceX96, int24 tick,,) = s_poolManager.getSlot0(key.toId());

            if (tick >= params.tickLower && tick <= params.tickUpper) {
                _disburseInterest();
            }
            _adjustExchangeRate(sqrtPriceX96, false);
        }
        return this.beforeRemoveLiquidity.selector;
    }

    /// @inheritdoc BaseHook
    function beforeSwap(
        address sender,
        PoolKey calldata, /*key*/
        IPoolManager.SwapParams calldata, /*params*/
        bytes calldata /*hookData*/
    ) external override noDelegateCall poolManagerOnly returns (bytes4, BeforeSwapDelta, uint24) {
        if (sender != address(this)) {
            _disburseInterest();
        }
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    /// @inheritdoc BaseHook
    function afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams memory params,
        BalanceDelta delta,
        bytes calldata /*hookData*/
    ) external override noDelegateCall poolManagerOnly returns (bytes4, int128) {
        if (sender != address(this)) {
            IPoolManager poolManager = s_poolManager;
            (uint256 sqrtPriceX96,, uint24 protocolFee, uint24 lpFee) = poolManager.getSlot0(key.toId());

            // if a swap cause the price to go below 1, we need to do a reverse swap
            if (sqrtPriceX96 <= Constants.ONE_Q96) {
                uint128 amount = _amountBeforeFee(_amountBeforeFee(uint128(delta.amount0()), lpFee), protocolFee);

                params = IPoolManager.SwapParams(false, -int128(amount), Constants.MAX_SQRT_PRICE_Q96 - 1);
                delta = poolManager.swap(s_poolKey, params, "");

                _mint(address(poolManager), amount);
                poolManager.settle(Currency.wrap(address(this)));
                poolManager.take(CurrencyLibrary.NATIVE, address(this), uint128(delta.amount0()));
            }
        }
    }

    /// @notice Helper function to disburse interest to active liquidity providers, as frequently as each block
    function _disburseInterest() private {
        (uint256 interestDeflatorGrowthUD18,) = s_deflators.grow(_calculateInterestRate(), feeRate());

        if (interestDeflatorGrowthUD18 > 0) {
            uint256 interest = mulDiv18(s_positions[GLOBAL_POSITION_ID].realDebt, interestDeflatorGrowthUD18);

            IPoolManager poolManager = s_poolManager;
            poolManager.donate(s_poolKey, 0, interest, "");
            _mint(address(poolManager), interest);
            poolManager.settle(Currency.wrap(address(this)));
        }
    }

    /// @notice Helper function to add some amount of a fungible to a position
    /// @param positionId The ID of the position
    /// @param fungible The fungible to add
    /// @param amount The amount to add
    function _addFungible(uint256 positionId, Fungible fungible, uint256 amount) private {
        Position storage s_globalPosition = s_positions[GLOBAL_POSITION_ID];

        uint256 received = fungible.balanceOf(address(this)) - s_globalPosition.fungibleAssets[fungible].balance
            - (fungible == FungibleLibrary.NATIVE ? s_surplus : 0);
        if (received < amount) revert FungibleAmountNotRecieved();

        s_positions[positionId].addFungible(fungible, amount);
        s_globalPosition.addFungible(fungible, amount);
    }

    /// @notice Helper function to remove some amount of a fungible from a position
    /// @param positionId The position ID
    /// @param fungible The fungible to remove
    /// @param amount The amount to remove
    function _removeFungible(uint256 positionId, Fungible fungible, uint256 amount) private {
        Position storage s_position = s_positions[positionId];
        if (s_position.fungibleAssets[fungible].balance < amount) revert FungibleBalanceInsufficient();

        s_position.removeFungible(fungible, amount);
        s_positions[GLOBAL_POSITION_ID].removeFungible(fungible, amount);
    }

    /// @notice Helper function to adjust the exchange rate based on the square root price
    /// @param sqrtPriceX96 The square root price in Q96
    /// @param hasSqrtPriceChanged Whether the square root price has changed
    function _adjustExchangeRate(uint256 sqrtPriceX96, bool hasSqrtPriceChanged) private {
        uint256 targetExchangeRateUD18 =
            mulDiv(mulDiv(sqrtPriceX96, sqrtPriceX96, Constants.ONE_Q96), Constants.ONE_UD18, Constants.ONE_Q96);
        assert(targetExchangeRateUD18 > Constants.ONE_UD18); // target exchange rate must be greater than 1

        s_exchangeRate.adjust(targetExchangeRateUD18, hasSqrtPriceChanged, maxExchangeRateAdjRatio());
    }

    /// @notice Helper function to calculate the interest rate
    /// @return uint The interest rate in UD18
    function _calculateInterestRate() private view returns (uint256) {
        InterestMode interestMode = interestMode();
        uint40 maxInterestRateUD18 = maxInterestRate();
        uint256 exchangeRateUD18 = s_exchangeRate.currentUD18;

        uint256 annualInterestRateUD18 = (
            interestMode == InterestMode.Intensified
                ? mulDiv18(exchangeRateUD18, exchangeRateUD18)
                : (interestMode == InterestMode.Normal ? exchangeRateUD18 : sqrt(exchangeRateUD18))
        ) - Constants.ONE_UD18;
        uint256 interestRateUD18 = annualInterestRateUD18 / Constants.SECONDS_PER_YEAR;

        return interestRateUD18 >= maxInterestRateUD18 ? maxInterestRateUD18 : interestRateUD18;
    }

    /// @notice Helper function to calculate the amount to swap before fees
    /// @param amount The amount to swap
    /// @param fee The fee in pips
    /// @return uin128 The amount to swap before fees
    function _amountBeforeFee(uint128 amount, uint24 fee) private pure returns (uint128) {
        uint256 amountBeforeFee = mulDiv(amount, Constants.ONE_PIPS, Constants.ONE_PIPS - fee) + 1; // lazy rounding up
        assert(amountBeforeFee < type(uint128).max); // overflow protection

        return uint128(amountBeforeFee);
    }
}
