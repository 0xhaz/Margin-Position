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
}
