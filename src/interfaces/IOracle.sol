// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import {Fungible} from "src/types/Fungible.sol";
import {NonFungible} from "src/types/NonFungible.sol";

/// @notice Interface for oracles
interface IOracle {
    /// @notice Quotes the value of some amount of a fungible in the native fungible
    /// @param fungible The fungible to quote
    /// @param amount The amount to quote
    /// @param data Additional data for the quote
    /// @return valueInNative The value in the native fungible
    function quoteFungibleInNative(Fungible fungible, uint256 amount, bytes calldata data)
        external
        view
        returns (uint256 valueInNative);

    /// @notice Quotes the value of a non-fungible in the native fungible
    /// @param nonFungible The non-fungible to quote
    /// @param item The item to quote
    /// @param data Additional data for the quote
    /// @return valueInNative The value in the native fungible
    function quoteNonFungibleInNative(NonFungible nonFungible, uint256 item, bytes calldata data)
        external
        view
        returns (uint256 valueInNative);

    /// @notice Decomposes a non-fungible into its fungible components
    /// @param nonFungible The non-fungible to decompose
    /// @param item The item to decompose
    /// @param data Additional data for the decomposition
    /// @return fungibles The fungibles that make up the non-fungible
    /// @return amounts The amounts of each fungible obtained from the decomposition
    function decomposeNonFungible(NonFungible nonFungible, uint256 item, bytes calldata data)
        external
        view
        returns (Fungible[] memory fungibles, uint256[] memory amounts);
}
