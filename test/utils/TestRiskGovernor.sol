// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IRiskConfigs, IRiskGovernor, IOracle} from "../../src/interfaces/IRiskConfigs.sol";

contract TestRiskGovernor is IRiskGovernor {
    function appointNextRiskGovernor(IRiskConfigs riskConfigs, IRiskGovernor riskGovernorNext) external {
        riskConfigs.appointNextRiskGovernor(riskGovernorNext);
    }

    function confirmRiskGovernor(IRiskConfigs riskConfigs) external {
        riskConfigs.confirmRiskGovernor();
    }

    function setFeeRate(IRiskConfigs riskConfigs, uint32 feeRateUD18) external {
        riskConfigs.setFeeRate(feeRateUD18);
    }

    function setInterestMode(IRiskConfigs riskConfigs, IRiskConfigs.InterestMode interestMode) external {
        riskConfigs.setInterestMode(interestMode);
    }

    function setMaxInterestRate(IRiskConfigs riskConfigs, uint40 maxInterestRateUD18) external {
        riskConfigs.setMaxInterestRate(maxInterestRateUD18);
    }

    function setMaxDebtRatio(IRiskConfigs riskConfigs, uint64 maxDebtRatioUD18) external {
        riskConfigs.setMaxDebtRatio(maxDebtRatioUD18);
    }

    function setMaxExchangeRateAdjRatio(IRiskConfigs riskConfigs, uint64 maxExchangeRateAdjRatioUD18) external {
        riskConfigs.setMaxExchangeRateAdjRatio(maxExchangeRateAdjRatioUD18);
    }

    function setAssetMarginReqRatio(IRiskConfigs riskConfigs, address asset, uint64 marginReqRatioUD18) external {
        riskConfigs.setAssetMarginReqRatio(asset, marginReqRatioUD18);
    }

    function setAssetOracle(IRiskConfigs riskConfigs, address asset, IOracle oracle, bytes calldata oracleData)
        external
    {
        riskConfigs.setAssetOracle(asset, oracle, oracleData);
    }
}
