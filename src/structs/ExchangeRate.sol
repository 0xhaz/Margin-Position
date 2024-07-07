// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import {mulDiv18} from "prb-math/Common.sol";

/// @notice Struct for representing exchange rates
struct ExchangeRate {
    uint256 currentUD18;
    uint256 previousUD18;
    uint256 lastAdjTimestamp;
}

using ExchangeRateLibrary for ExchangeRate global;

/// @notice Library for working with exchange rate
library ExchangeRateLibrary {
    /// @notice Thrown when trying to initialize an already initialized exchange rate
    error ExchangeRateAlreadyInitialized();

    /// @notice Initializes the exchange rate
    /// @param s_self The exchange rate to initialize
    function initialize(ExchangeRate storage s_self, uint256 exchangeRateUD18) internal {
        if (s_self.lastAdjTimestamp != 0) revert ExchangeRateAlreadyInitialized();

        s_self.currentUD18 = exchangeRateUD18;
        s_self.previousUD18 = exchangeRateUD18;
        s_self.lastAdjTimestamp = block.timestamp;
    }

    /// @notice Adjusts the exchange rate towrds a target, capped by a maximum adjustment ratio per block
    /// @param s_self The exchange rate to adjust
    /// @param targetUD18 The target exchange rate in UD18
    /// @param isNewTarget whether the target is new (different from the last target)
    /// @param maxAdjRatioUD18 the maximum adjustment ratio in UD18
    function adjust(ExchangeRate storage s_self, uint256 targetUD18, bool isNewTarget, uint256 maxAdjRatioUD18)
        internal
    {
        uint256 currentUD18 = s_self.currentUD18;

        if (currentUD18 != targetUD18) {
            bool isNewBlock = block.timestamp > s_self.lastAdjTimestamp;

            if (isNewBlock || isNewTarget) {
                if (isNewBlock) {
                    s_self.previousUD18 = currentUD18;
                    s_self.lastAdjTimestamp = block.timestamp;
                }

                uint256 previousUD18 = isNewBlock ? currentUD18 : s_self.previousUD18;
                uint256 maxAdjUD18 = mulDiv18(previousUD18, maxAdjRatioUD18);
                uint256 ceilingUD18 = previousUD18 + maxAdjUD18;
                uint256 floorUD18 = previousUD18 - maxAdjUD18;

                if (targetUD18 >= ceilingUD18) {
                    if (currentUD18 != ceilingUD18) {
                        s_self.currentUD18 = ceilingUD18;
                    }
                } else if (targetUD18 <= floorUD18) {
                    if (currentUD18 != floorUD18) {
                        s_self.currentUD18 = floorUD18;
                    }
                } else {
                    s_self.currentUD18 = targetUD18;
                }
            }
        }
    }
}
