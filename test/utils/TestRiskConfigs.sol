// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {RiskConfigs, IRiskGovernor} from "../../src/modules/RiskConfigs.sol";

contract TestRiskConfigs is RiskConfigs {
    constructor(IRiskGovernor riskGovernor) RiskConfigs(riskGovernor, RiskParams(InterestMode.Normal, 0, 0, 0, 0)) {}
}
