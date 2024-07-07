// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import {mulDiv18} from "prb-math/Common.sol";
import {IRiskConfigs, IOracle} from "src/interfaces/IRiskConfigs.sol";
import {Fungible} from "src/types/Fungible.sol";
import {NonFungible} from "src/types/NonFungible.sol";

/// @notice Struct for representing fungible asset
struct FungibleAsset {
    uint256 index; // one-based index of the fungible in the fungibles array
    uint256 balance;
}

/// @notice Struct for representing non-fungible asset
struct NonFungibleAsset {
    uint256 index; // one-based index of the non-fungible in the nonFungibles array
    uint256[] items;
    mapping(uint256 => uint256) itemIndices; // one-based index of the item in the items array
}

/// @notice Struct for representing position
struct Position {
    address owner;
    address originator;
    uint256 realDebt; // sum of outstanding debts deflated to a common point in time
    Fungible[] fungibles;
    mapping(Fungible => FungibleAsset) fungibleAssets;
    NonFungible[] nonFungibles;
    mapping(NonFungible => NonFungibleAsset) nonFungibleAssets;
}

using PositionLibrary for Position global;

/// @notice Library for working with position
library PositionLibrary {
    /// @notice Thrown when trying to open an already opened position
    error PositionAlreadyExists();

    /// @notice Thrown when trying to close a position that is not empty
    error PositionIsNotEmpty();

    /// @notice Thrown when trying to add non-fungible item that is already in the position
    error PositionAlreadyContainsNonFungibleItem();

    /// @notice Thrown when trying to remove a non-fungible item that is not in the position
    error PositionDoesNotContainNonFungibleItem();

    /// @notice Opens a position
    /// @param s_self The position to open
    /// @param owner The owner of the position
    /// @param originator The originator of the position
    function open(Position storage s_self, address owner, address originator) internal {
        if (s_self.exists()) revert PositionAlreadyExists();

        s_self.owner = owner;
        if (originator != address(0)) {
            s_self.originator = originator;
        }
    }

    /// @notice Closes a position
    /// @param s_self The position to close
    function close(Position storage s_self) internal {
        if (!s_self.isEmpty()) revert PositionIsNotEmpty();

        delete s_self.owner;
        delete s_self.originator;
    }

    /// @notice Adds some amount of a fungible to the position
    /// @param s_self The position to add the fungible to
    /// @param fungible The fungible to add
    /// @param amount The amount of the fungible to add
    function addFungible(Position storage s_self, Fungible fungible, uint256 amount) internal {
        FungibleAsset storage s_fungibleAsset = s_self.fungibleAssets[fungible];
        uint256 oldBalance = s_fungibleAsset.balance;

        if (oldBalance == 0) {
            s_self.fungibles.push(fungible);
            s_fungibleAsset.index = s_self.fungibles.length;
        }
        s_fungibleAsset.balance = oldBalance + amount; // overflow is desired
    }

    /// @notice Removes some amount of a fungible from a position
    /// @param s_self The position to remove the fungible from
    /// @param fungible The fungible to remove
    /// @param amount The amount of the fungible to remove
    function removeFungible(Position storage s_self, Fungible fungible, uint256 amount) internal {
        FungibleAsset storage s_fungibleAsset = s_self.fungibleAssets[fungible];
        uint256 newBalance = s_fungibleAsset.balance - amount; // underflow is desired

        if (newBalance == 0) {
            uint256 index = s_fungibleAsset.index;
            uint256 lastIndex = s_self.fungibles.length;
            assert(index > 0 && index <= lastIndex); // sanity check

            // underflow or index out of bounds not possible
            unchecked {
                if (index != lastIndex) {
                    Fungible lastFungible = s_self.fungibles[lastIndex - 1];

                    s_self.fungibles[index - 1] = lastFungible;
                    s_self.fungibleAssets[lastFungible].index = index;
                }
            }
            s_self.fungibles.pop();
            delete s_self.fungibleAssets[fungible];
        } else {
            s_fungibleAsset.balance = newBalance;
        }
    }

    /// @notice Adds a non-fungible item to a position
    /// @param s_self The position to add the non-fungible item to
    /// @param nonFungible the non-fungible item to add
    /// @param item the item to add
    function addNonFungible(Position storage s_self, NonFungible nonFungible, uint256 item) internal {
        NonFungibleAsset storage s_nonFungibleAsset = s_self.nonFungibleAssets[nonFungible];
        if (s_nonFungibleAsset.itemIndices[item] != 0) revert PositionAlreadyContainsNonFungibleItem();
        uint256 itemsCount = s_nonFungibleAsset.items.length;

        if (itemsCount == 0) {
            s_self.nonFungibles.push(nonFungible);
            s_nonFungibleAsset.index = s_self.nonFungibles.length;
        }
        s_nonFungibleAsset.items.push(item);
        s_nonFungibleAsset.itemIndices[item] = itemsCount + 1;
    }

    /// @notice Removes a non-fungible item from a position
    /// @param s_self The position to remove the non-fungible item from
    /// @param nonFungible The non-fungible item to remove
    /// @param item The item to remove
    function removeNonFungible(Position storage s_self, NonFungible nonFungible, uint256 item) internal {
        NonFungibleAsset storage s_nonFungibleAsset = s_self.nonFungibleAssets[nonFungible];
        if (s_nonFungibleAsset.itemIndices[item] == 0) revert PositionDoesNotContainNonFungibleItem();
        uint256 itemsCount = s_nonFungibleAsset.items.length;

        if (itemsCount == 1) {
            uint256 index = s_nonFungibleAsset.index;
            uint256 lastIndex = s_self.nonFungibles.length;
            assert(index > 0 && index <= lastIndex); // sanity check

            // underflow or index out of bounds not possible
            unchecked {
                if (index != lastIndex) {
                    NonFungible lastNonFungible = s_self.nonFungibles[lastIndex - 1];

                    s_self.nonFungibles[index - 1] = lastNonFungible;
                    s_self.nonFungibleAssets[lastNonFungible].index = index;
                }
            }
            s_self.nonFungibles.pop();
            delete s_nonFungibleAsset.itemIndices[item]; // extra hygiene
            delete s_self.nonFungibleAssets[nonFungible];
        } else {
            uint256 itemIndex = s_nonFungibleAsset.itemIndices[item];
            uint256 lastItemIndex = itemsCount;
            assert(itemIndex > 0 && itemIndex <= lastItemIndex); // sanity check

            // underflow or index out of bounds not possible
            unchecked {
                if (itemIndex != lastItemIndex) {
                    uint256 lastItem = s_nonFungibleAsset.items[lastItemIndex - 1];

                    s_nonFungibleAsset.items[itemIndex - 1] = lastItem;
                    s_nonFungibleAsset.itemIndices[lastItem] = itemIndex;
                }
            }
            s_nonFungibleAsset.items.pop();
            delete s_nonFungibleAsset.itemIndices[item];
        }
    }

    /// @notice Checks if a position exists
    /// @param s_self The position to check
    /// @return bool True if the position exists, else false
    function exists(Position storage s_self) internal view returns (bool) {
        return s_self.owner != address(0);
    }

    /// @notice Checks is a position is empty
    /// @param s_self The position to check
    /// @return bool True if the position is empty, else false
    function isEmpty(Position storage s_self) internal view returns (bool) {
        return s_self.realDebt == 0 && s_self.fungibles.length == 0 && s_self.nonFungibles.length == 0;
    }

    /// @notice Gets the nominal debt of a position
    /// @param s_self The position to get the nominal debt of
    /// @param deflatorUD18 The deflator in UD18
    /// @return uint the nominal debt
    function nominalDebt(Position storage s_self, uint256 deflatorUD18) internal view returns (uint256) {
        return mulDiv18(s_self.realDebt, deflatorUD18) + 1; // lazy round up
    }

    /// @notice Appraises a position, get its value and margin requirement in quote fungible
    /// @param s_self The position to appraise
    /// @param riskConfigs The risk configs
    /// @param quoteFungible The quote fungible
    /// @param exchangeRateUD18 The exchange rate between the quote and the native fungibles in UD18
    function appraise(
        Position storage s_self,
        IRiskConfigs riskConfigs,
        Fungible quoteFungible,
        uint256 exchangeRateUD18
    ) internal view returns (uint256 value, uint256 marginReq) {
        uint256 baseValue; // tracks value in the native fungible
        uint256 baseMarginReq; // tracks margin requirement in the native fungible

        Fungible[] memory fungibles = s_self.fungibles;
        uint256 len = fungibles.length;
        for (uint256 i; i < len; ++i) {
            Fungible fungible = fungibles[i];
            uint256 amount = s_self.fungibleAssets[fungible].balance;

            if (fungible == quoteFungible) {
                value += amount;
            } else {
                (uint256 baseValue_, uint256 baseMarginReq_) = _appraiseFungibleInNative(fungible, amount, riskConfigs);

                baseValue += baseValue_;
                baseMarginReq += baseMarginReq_;
            }
        }

        NonFungible[] memory nonFungibles = s_self.nonFungibles;
        len = nonFungibles.length;
        for (uint256 i; i < len; ++i) {
            NonFungible nonFungible = nonFungibles[i];
            (uint64 marginReqRatioUD18, IOracle oracle, bytes memory oracleData) =
                riskConfigs.riskParamsOf(NonFungible.unwrap(nonFungible));

            if (address(oracle) == address(0)) continue; // skip unsupported non-fungible
            uint256[] memory items = s_self.nonFungibleAssets[nonFungible].items;
            uint256 itemsLen = items.length;

            if (marginReqRatioUD18 != 0) {
                // we can appraise the non-fungible as a whole
                for (uint256 j; j < itemsLen; ++j) {
                    uint256 baseValue_ = oracle.quoteNonFungibleInNative(nonFungible, items[j], oracleData);

                    baseValue += baseValue_;
                    baseMarginReq += mulDiv18(baseValue_, marginReqRatioUD18) + 1; // lazy round up
                }
            } else {
                // we need to decompose the non-fungible
                for (uint256 j; j < itemsLen; ++j) {
                    (Fungible[] memory fungibles_, uint256[] memory amounts) =
                        oracle.decomposeNonFungible(nonFungible, items[j], oracleData);

                    uint256 fungiblesLen = fungibles_.length;
                    for (uint256 k; k < fungiblesLen; ++k) {
                        if (fungibles_[k] == quoteFungible) {
                            value += amounts[k];
                        } else {
                            (uint256 baseValue_, uint256 baseMarginReq_) =
                                _appraiseFungibleInNative(fungibles_[k], amounts[k], riskConfigs);

                            baseValue += baseValue_;
                            baseMarginReq += baseMarginReq_;
                        }
                    }
                }
            }
        }

        value += mulDiv18(baseValue, exchangeRateUD18);
        marginReq += mulDiv18(baseMarginReq, exchangeRateUD18) + 1;
    }

    /// @notice Helper function to appraise some amount of a fungible in the native fungible
    /// @param fungible The fungible to appraise
    /// @param amount The amount of the fungible to appraise
    /// @param riskConfigs The risk configs
    /// @return valueInNative the value in the native fungible
    /// @return marginReqInNative the margin requirement in the native fungible
    function _appraiseFungibleInNative(Fungible fungible, uint256 amount, IRiskConfigs riskConfigs)
        private
        view
        returns (uint256 valueInNative, uint256 marginReqInNative)
    {
        (uint64 margineReqRatioUD18, IOracle oracle, bytes memory oracleData) =
            riskConfigs.riskParamsOf(Fungible.unwrap(fungible));

        // skip unsupported fungible
        if (address(oracle) != address(0)) {
            valueInNative = oracle.quoteFungibleInNative(fungible, amount, oracleData);
            marginReqInNative = mulDiv18(valueInNative, margineReqRatioUD18) + 1; // lazy round up
        }
    }
}
