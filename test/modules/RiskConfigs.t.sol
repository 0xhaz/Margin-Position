// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IRiskConfigs, IOracle} from "src/interfaces/IRiskConfigs.sol";
import {Constants} from "src/utils/Constants.sol";
import {TestRiskConfigs} from "test/utils/TestRiskConfigs.sol";
import {TestRiskGovernor} from "test/utils/TestRiskGovernor.sol";

contract RiskConfigTest is Test {
    TestRiskGovernor riskGovernor1 = new TestRiskGovernor();
    TestRiskGovernor riskGovernor2 = new TestRiskGovernor();

    TestRiskConfigs riskConfigs;

    function setUp() public {
        riskConfigs = new TestRiskConfigs(riskGovernor1);
    }

    function test_Appoint_And_Confirm_Risk_Governor() public {
        vm.expectRevert(IRiskConfigs.NotRiskGovernor.selector);
        riskGovernor2.appointNextRiskGovernor(riskConfigs, riskGovernor1);

        riskGovernor1.appointNextRiskGovernor(riskConfigs, riskGovernor2);
        riskGovernor2.confirmRiskGovernor(riskConfigs);

        vm.expectRevert(IRiskConfigs.NotRiskGovernor.selector);
        riskGovernor1.appointNextRiskGovernor(riskConfigs, riskGovernor2);

        vm.expectRevert(IRiskConfigs.NotRiskGovernorNext.selector);
        riskGovernor2.confirmRiskGovernor(riskConfigs);
    }

    function testFuzz_SetAndGetFeeRate(uint32 feeRateUD18) public {
        vm.expectRevert(IRiskConfigs.NotRiskGovernor.selector);
        riskGovernor2.setFeeRate(riskConfigs, feeRateUD18);

        if (feeRateUD18 > Constants.ONE_BILLIONTH_UD18) {
            vm.expectRevert(IRiskConfigs.InvalidFeeRate.selector);
            riskGovernor1.setFeeRate(riskConfigs, feeRateUD18);
        } else {
            riskGovernor1.setFeeRate(riskConfigs, feeRateUD18);
            assertEq(riskConfigs.feeRate(), feeRateUD18);
        }
    }

    function testFuzz_SetAndGetInterestMode(uint8 enumVal) public {
        enumVal = uint8(bound(enumVal, 0, 2));
        IRiskConfigs.InterestMode interestMode = IRiskConfigs.InterestMode(enumVal);

        vm.expectRevert(IRiskConfigs.NotRiskGovernor.selector);
        riskGovernor2.setInterestMode(riskConfigs, interestMode);

        riskGovernor1.setInterestMode(riskConfigs, interestMode);
        assert(riskConfigs.interestMode() == interestMode);
    }

    function testFuzz_SetAndGetMaxInterestRate(uint40 maxInterestRateUD18) public {
        vm.expectRevert(IRiskConfigs.NotRiskGovernor.selector);
        riskGovernor2.setMaxInterestRate(riskConfigs, maxInterestRateUD18);

        if (maxInterestRateUD18 == 0 || maxInterestRateUD18 > Constants.ONE_HUNDRED_MILLIONTH_UD18) {
            vm.expectRevert(IRiskConfigs.InvalidMaxInterestRate.selector);
            riskGovernor1.setMaxInterestRate(riskConfigs, maxInterestRateUD18);
        } else {
            riskGovernor1.setMaxInterestRate(riskConfigs, maxInterestRateUD18);
            assertEq(riskConfigs.maxInterestRate(), maxInterestRateUD18);
        }
    }

    function testFuzz_SetAndGetAssetRiskParams(address asset, uint64 marginReqRatioUD18) public {
        uint64 marginReqRatioUD18_;
        IOracle oracle_;
        bytes memory oracleData_;

        vm.expectRevert(IRiskConfigs.NotRiskGovernor.selector);
        riskGovernor2.setAssetMarginReqRatio(riskConfigs, asset, marginReqRatioUD18);

        vm.expectRevert(IRiskConfigs.InvalidAssetMarginReqRatio.selector);
        riskGovernor1.setAssetMarginReqRatio(riskConfigs, asset, marginReqRatioUD18);

        riskGovernor1.setAssetOracle(riskConfigs, asset, IOracle(address(1)), "test");
        if (marginReqRatioUD18 > Constants.ONE_UD18) {
            vm.expectRevert(IRiskConfigs.InvalidAssetMarginReqRatio.selector);
            riskGovernor1.setAssetMarginReqRatio(riskConfigs, asset, marginReqRatioUD18);
        } else {
            riskGovernor1.setAssetMarginReqRatio(riskConfigs, asset, marginReqRatioUD18);
            (marginReqRatioUD18_, oracle_, oracleData_) = riskConfigs.riskParamsOf(asset);
            assertEq(marginReqRatioUD18_, marginReqRatioUD18);
            assertEq(address(oracle_), address(1));
            assertEq(oracleData_, "test");

            riskGovernor1.setAssetOracle(riskConfigs, asset, IOracle(address(0)), "test");
            (marginReqRatioUD18_, oracle_, oracleData_) = riskConfigs.riskParamsOf(asset);
            assertEq(marginReqRatioUD18_, 0);
            assertEq(address(oracle_), address(0));
            assertEq(oracleData_, "");
        }
    }
}
