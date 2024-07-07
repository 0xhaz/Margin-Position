// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import {mulDiv18} from "prb-math/Common.sol";
import {UD60x18, powu} from "prb-math/UD60x18.sol";
import {Constants} from "src/utils/Constants.sol";

/// @notice Struct for representing deflators
struct Deflators {
    uint256 interestUD18;
    uint256 interestAndFeeUD18;
    uint256 lastGrowthTimestamp;
}

using DeflatorsLibrary for Deflators global;

/// @notice Library for deflators
library DeflatorsLibrary {
    /// @notice Thrown when trying to initialize an already initialized deflators
    error DeflatorsAlreadyInitialized();

    /// @notice Initializes the deflators
    /// @param s_self The deflators to initialize
    function initialize(Deflators storage s_self) internal {
        if (s_self.lastGrowthTimestamp != 0) revert DeflatorsAlreadyInitialized();

        s_self.interestUD18 = Constants.ONE_UD18;
        s_self.interestAndFeeUD18 = Constants.ONE_UD18;
        s_self.lastGrowthTimestamp = block.timestamp;
    }

    /// @notice Grows the deflators for the time elapsed since the last growth
    /// @param s_self The deflators to grow
    /// @param interestRateUD18 The interest rate in UD18
    /// @param feeRateUD18 The fee rate in UD18
    /// @return interestDeflatorGrowthUD18 The growth of the interest deflator in UD18
    /// @return interestAndFeeDeflatorGrowthUD18 The growth of the interest and fee deflator in UD18
    function grow(Deflators storage s_self, uint256 interestRateUD18, uint256 feeRateUD18)
        internal
        returns (uint256 interestDeflatorGrowthUD18, uint256 interestAndFeeDeflatorGrowthUD18)
    {
        uint256 timeElapsed = block.timestamp - s_self.lastGrowthTimestamp;

        if (timeElapsed > 0) {
            uint256 interestDeflatorUD18 = s_self.interestUD18;
            interestDeflatorGrowthUD18 = mulDiv18(interestDeflatorUD18, _compoundRate(interestRateUD18, timeElapsed));
            s_self.interestUD18 = interestDeflatorUD18 + interestDeflatorGrowthUD18;

            uint256 interestAndFeeDeflatorUD18 = s_self.interestAndFeeUD18;
            interestAndFeeDeflatorGrowthUD18 =
                mulDiv18(interestAndFeeDeflatorUD18, _compoundRate(interestRateUD18 + feeRateUD18, timeElapsed));
            s_self.interestAndFeeUD18 = interestAndFeeDeflatorUD18 + interestAndFeeDeflatorGrowthUD18;

            s_self.lastGrowthTimestamp = block.timestamp;
        }
    }

    /// @notice Helper function to compound a rate
    /// @param rateUD18 The rate in UD18
    /// @param power The power to raise the rate to
    /// @return uint The compounded rate in UD18
    function _compoundRate(uint256 rateUD18, uint256 power) private pure returns (uint256) {
        return UD60x18.unwrap(powu(UD60x18.wrap(Constants.ONE_UD18 + rateUD18), power)) - Constants.ONE_UD18;
    }
}
