// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import {IRiskConfigs, IRiskGovernor, IOracle} from "src/interfaces/IRiskConfigs.sol";
import {Constants} from "src/utils/Constants.sol";

/// @notice Abstract contract for implementing risk configurations
abstract contract RiskConfigs is IRiskConfigs {
    struct RiskParams {
        InterestMode interestMode;
        uint32 feeRateUD18;
        uint40 maxInterestRateUD18;
        uint64 maxDebtRatioUD18;
        uint64 maxExchangeRateAdjRatioUD18;
    }

    struct AssetRiskParams {
        uint256 index; // one-based index of the asset in the assets array
        uint64 marginReqRatioUD18;
        IOracle oracle;
        bytes oracleData;
    }

    IRiskGovernor private s_riskGovernor;
    IRiskGovernor private s_riskGovernorNext;

    RiskParams private s_riskParams;
    address[] private s_assets;
    mapping(address => AssetRiskParams) private s_assetRiskParams;

    /// @notice Modifier for functions that can only be called by the risk governor
    modifier riskGovernorOnly() {
        if (msg.sender != address(s_riskGovernor)) revert NotRiskGovernor();
        _;
    }

    constructor(IRiskGovernor riskGovernor, RiskParams memory riskParams) {
        s_riskGovernor = riskGovernor;
        s_riskParams = riskParams;

        emit RiskGovernorConfirmed(riskGovernor);
        emit InterestModeUpdated(riskParams.interestMode);
        emit FeeRateUpdated(riskParams.feeRateUD18);
        emit MaxDebtRatioUpdated(riskParams.maxDebtRatioUD18);
        emit MaxInterestRateUpdated(riskParams.maxInterestRateUD18);
    }

    /// @inheritdoc IRiskConfigs
    function appointNextRiskGovernor(IRiskGovernor riskGovernorNext) external riskGovernorOnly {
        s_riskGovernorNext = riskGovernorNext;

        emit RiskGovernorAppointed(riskGovernorNext);
    }

    /// @inheritdoc IRiskConfigs
    function confirmRiskGovernor() external {
        IRiskGovernor riskGovernorNext = s_riskGovernorNext;
        if (msg.sender != address(riskGovernorNext)) revert NotRiskGovernorNext();

        s_riskGovernor = riskGovernorNext;
        delete s_riskGovernorNext;

        emit RiskGovernorConfirmed(riskGovernorNext);
    }

    /// @inheritdoc IRiskConfigs
    function setFeeRate(uint32 feeRateUD18) external riskGovernorOnly {
        if (feeRateUD18 > Constants.ONE_BILLIONTH_UD18) revert InvalidFeeRate();

        s_riskParams.feeRateUD18 = feeRateUD18;

        emit FeeRateUpdated(feeRateUD18);
    }

    /// @inheritdoc IRiskConfigs
    function setInterestMode(InterestMode interestMode_) external riskGovernorOnly {
        s_riskParams.interestMode = interestMode_;

        emit InterestModeUpdated(interestMode_);
    }

    /// @inheritdoc IRiskConfigs
    function setMaxInterestRate(uint40 maxInterestRateUD18) external riskGovernorOnly {
        if (maxInterestRateUD18 == 0 || maxInterestRateUD18 > Constants.ONE_HUNDREDTH_MILLIONTH_UD18) {
            revert InvalidMaxInterestRate();
        }

        s_riskParams.maxInterestRateUD18 = maxInterestRateUD18;

        emit MaxInterestRateUpdated(maxInterestRateUD18);
    }

    /// @inheritdoc IRiskConfigs
    function setMaxDebtRatio(uint64 maxDebtRatioUD18) external riskGovernorOnly {
        if (maxDebtRatioUD18 > Constants.ONE_UD18) revert InvalidMaxDebtRatio();

        s_riskParams.maxDebtRatioUD18 = maxDebtRatioUD18;

        emit MaxDebtRatioUpdated(maxDebtRatioUD18);
    }

    /// @inheritdoc IRiskConfigs
    function setMaxExchangeRateAdjRatio(uint64 maxExchangeRateAdjRatioUD18) external riskGovernorOnly {
        if (maxExchangeRateAdjRatioUD18 == 0 || maxExchangeRateAdjRatioUD18 > Constants.ONE_UD18) {
            revert InvalidMaxExchangeRateAdjRatio();
        }

        s_riskParams.maxExchangeRateAdjRatioUD18 = maxExchangeRateAdjRatioUD18;
    }

    /// @inheritdoc IRiskConfigs
    function setAssetMarginReqRatio(address asset, uint64 marginReqRatioUD18) external riskGovernorOnly {
        // only allow margin requirement if oracle is set, and must be [(1 - maxDebtRatio), 1]
        if (address(s_assetRiskParams[asset].oracle) == address(0) || marginReqRatioUD18 > Constants.ONE_UD18) {
            revert InvalidAssetMarginReqRatio();
        }

        s_assetRiskParams[asset].marginReqRatioUD18 = marginReqRatioUD18;

        emit AssetMarginReqRatioUpdated(asset, marginReqRatioUD18);
    }

    /// @inheritdoc IRiskConfigs
    function setAssetOracle(address asset, IOracle oracle, bytes calldata oracleData) external riskGovernorOnly {
        if (address(oracle) == address(0)) {
            // clear asset risk parameters if oracle is set to zero address
            uint256 index = s_assetRiskParams[asset].index;
            uint256 lastIndex = s_assets.length;
            assert(index > 0 && index <= lastIndex); // sanity check

            // underflow or index out of bounds not possible
            unchecked {
                if (index != lastIndex) {
                    address lastAsset = s_assets[lastIndex - 1];

                    s_assets[index - 1] = lastAsset;
                    s_assetRiskParams[lastAsset].index = index;
                }
            }
            s_assets.pop();
            delete s_assetRiskParams[asset];
        } else {
            // add asset to array if setting oracle for the first time
            if (address(s_assetRiskParams[asset].oracle) == address(0)) {
                s_assets.push(asset);
                s_assetRiskParams[asset].index = s_assets.length;
            }

            s_assetRiskParams[asset].oracle = oracle;
            s_assetRiskParams[asset].oracleData = oracleData;
        }

        emit AssetOracleUpdated(asset, oracle, oracleData);
    }

    /// @inheritdoc IRiskConfigs
    function feeRate() public view returns (uint32) {
        return s_riskParams.feeRateUD18;
    }

    /// @inheritdoc IRiskConfigs
    function interestMode() public view returns (InterestMode) {
        return s_riskParams.interestMode;
    }

    /// @inheritdoc IRiskConfigs
    function maxInterestRate() public view returns (uint40) {
        return s_riskParams.maxInterestRateUD18;
    }

    /// @inheritdoc IRiskConfigs
    function maxDebtRatio() public view returns (uint64) {
        return s_riskParams.maxDebtRatioUD18;
    }

    /// @inheritdoc IRiskConfigs
    function maxExchangeRateAdjRatio() public view returns (uint64) {
        return s_riskParams.maxExchangeRateAdjRatioUD18;
    }

    /// @inheritdoc IRiskConfigs
    function riskParamsOf(address asset) public view returns (uint64, IOracle, bytes memory) {
        AssetRiskParams storage riskParams = s_assetRiskParams[asset];

        return (riskParams.marginReqRatioUD18, riskParams.oracle, riskParams.oracleData);
    }
}
