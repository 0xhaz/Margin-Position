// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import {IOracle} from "./IOracle.sol";
import {IRiskGovernor} from "./IRiskGovernor.sol";

/// @notice Interface for risk configurations
interface IRiskConfigs {
    enum InterestMode {
        Dampened,
        Normal,
        Intensified
    }

    /// @notice Emitted when the next risk governor is appointed
    /// @param riskGovernorNext the next risk governor
    event RiskGovernorAppointed(IRiskGovernor riskGovernorNext);

    /// @notice Emitted when the risk governor is confirmed
    /// @param riskGovernor The new risk governor
    event RiskGovernorConfirmed(IRiskGovernor riskGovernor);

    /// @notice Emitted when the fee rate is updated
    /// @param feeRateUD18 The new fee rate in UD18
    event FeeRateUpdated(uint32 feeRateUD18);

    /// @notice Emitted when the interest mode is updated
    /// @param interestMode The new interest mode
    event InterestModeUpdated(InterestMode interestMode);

    /// @notice Emitted when the maximum interest rate is updated
    /// @param maxInterestRateUD18 The new maximum interest rate in UD18
    event MaxInterestRateUpdated(uint40 maxInterestRateUD18);

    /// @notice Emitted when the maximum debt ratio is updated
    /// @param maxDebtRatiUD18 the new maximum debt ratio in UD18
    event MaxDebtRatioUpdated(uint64 maxDebtRatiUD18);

    /// @notice Emitted when the maximum exchange rate adjustment ratio is updated
    /// @param maxExchangeRateAdjRatioUD18 The new maximum exchange rate adjustment ratio in UD18
    event MaxExchangeRateAdjRatioUpdated(uint64 maxExchangeRateAdjRatioUD18);

    /// @notice Emitted when an asset's margin requirement ratio is updated
    /// @param asset The asset
    /// @param marginReqRatioUD18 The new margin requirement ratio in UD18
    event AssetMarginReqRatioUpdated(address indexed asset, uint64 marginReqRatioUD18);

    /// @notice Emitted when an asset's oracle and/or oracle data are updated
    /// @param asset the asset
    /// @param oracle the new oracle
    /// @param oracleData the new oracle data
    event AssetOracleUpdated(address indexed asset, IOracle oracle, bytes oracleData);

    /// @notice Thrown when the caller is not the risk governor.
    error NotRiskGovernor();

    /// @notice Thrown when the caller is not the next risk governor.
    error NotRiskGovernorNext();

    /// @notice Thrown when the fee rate is invalid.
    error InvalidFeeRate();

    /// @notice Thrown when the maximum interest rate is invalid.
    error InvalidMaxInterestRate();

    /// @notice Thrown when the maximum debt ratio is invalid.
    error InvalidMaxDebtRatio();

    /// @notice Thrown when the maximum exchange rate adjustment ratio is invalid.
    error InvalidMaxExchangeRateAdjRatio();

    /// @notice Thrown when the asset's margin requirement ratio is invalid.
    error InvalidAssetMarginReqRatio();

    /// @notice Appoints the next risk governor
    /// @param riskGovernorNext The next risk governor
    function appointNextRiskGovernor(IRiskGovernor riskGovernorNext) external;

    /// @notice Confirms the next risk governor
    function confirmRiskGovernor() external;

    /// @notice Sets the fee rate
    /// @param feeRateUD18 the fee rate in UD18
    function setFeeRate(uint32 feeRateUD18) external;

    /// @notice Sets the interest mode
    /// @param interestMode the interest mode
    function setInterestMode(InterestMode interestMode) external;

    /// @notice Sets the maximum interest rate
    /// @param maxInterestRateUD18 the maximum interest rate in UD18
    function setMaxInterestRate(uint40 maxInterestRateUD18) external;

    /// @notice Sets the maximum debt ratio
    /// @param maxDebtRatioUD18 the maximum debt ratio in UD18
    function setMaxDebtRatio(uint64 maxDebtRatioUD18) external;

    /// @notice Sets the maximum exchange rate adjustment ratio
    /// @param maxExchangeRateAdjRatioUD18 the maximum exchange rate adjustment ratio in UD18
    function setMaxExchangeRateAdjRatio(uint64 maxExchangeRateAdjRatioUD18) external;

    /// @notice Sets an asset's margin requirement ratio.
    /// @param asset The asset
    /// @param marginReqRatioUD18 The margin requirement ratio in UD18
    function setAssetMarginReqRatio(address asset, uint64 marginReqRatioUD18) external;

    /// @notice Sets an asset's oracle and oracle data.
    /// @param asset The asset
    /// @param oracle The oracle
    /// @param oracleData The oracle data
    function setAssetOracle(address asset, IOracle oracle, bytes calldata oracleData) external;

    /// @notice Gets the fee rate.
    /// @return feeRateUD18 The fee rate in UD18
    function feeRate() external view returns (uint32 feeRateUD18);

    /// @notice Gets the interest mode.
    /// @return interestMode The interest mode
    function interestMode() external view returns (InterestMode interestMode);

    /// @notice Gets the maximum interest rate.
    /// @return maxInterestRateUD18 The maximum interest rate in UD18
    function maxInterestRate() external view returns (uint40 maxInterestRateUD18);

    /// @notice Gets the maximum debt ratio.
    /// @return maxDebtRatioUD18 The maximum debt ratio in UD18
    function maxDebtRatio() external view returns (uint64 maxDebtRatioUD18);

    /// @notice Gets the maximum exchange rate adjustment ratio.
    /// @return maxExchangeRateAdjRatioUD18 The maximum exchange rate adjustment ratio in UD18
    function maxExchangeRateAdjRatio() external view returns (uint64 maxExchangeRateAdjRatioUD18);

    /// @notice Gets the risk parameters of an asset.
    /// @param asset The asset
    /// @return marginReqRatioUD18 The margin requirement ratio in UD18
    /// @return oracle The oracle
    /// @return oracleData The oracle data
    function riskParamsOf(address asset)
        external
        view
        returns (uint64 marginReqRatioUD18, IOracle oracle, bytes memory oracleData);
}
