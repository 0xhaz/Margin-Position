// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.0;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @notice Type for representing fungible assets
type Fungible is address;

using {equals as ==} for Fungible global;
using FungibleLibrary for Fungible global;

/// @notice Compares two fungibles for equality
/// @param a The first fungible
/// @param b The second fungible
/// @return bool Whether the fungibles are equal
function equals(Fungible a, Fungible b) pure returns (bool) {
    return Fungible.unwrap(a) == Fungible.unwrap(b);
}

/// @notice Library for working with fungibles, supports both native Ether (ETH) and ERC20 tokens
library FungibleLibrary {
    /// @notice Constant for representing the native Ether (ETH) asset
    Fungible public constant NATIVE = Fungible.wrap(address(0));

    /// @notice Thrown when a transfer fails
    error FungibleTransferFailed();

    /// @notice Transfers some amount of a fungible from the current contract to a recipient
    /// @dev Checks for success while accommodating non-standard ERC20s that do not return a boolean
    /// @param self The fungible to transfer
    /// @param to the recipient of the transfer
    /// @param amount The amount to transfer
    function transfer(Fungible self, address to, uint256 amount) internal {
        if (self == NATIVE) {
            (bool success,) = to.call{value: amount}("");
            if (!success) revert FungibleTransferFailed();
        } else {
            // accommodating non-standard ERC20s that do not return a boolean
            (bool success, bytes memory data) =
                Fungible.unwrap(self).call(abi.encodeCall(IERC20.transfer, (to, amount)));
            if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert FungibleTransferFailed();
        }
    }

    /// @notice Gets the balance of a owner
    /// @param self the fungible
    /// @param owner the owner to get the balance of
    /// @return uint The balance of the owner
    function balanceOf(Fungible self, address owner) internal view returns (uint256) {
        return self == NATIVE ? owner.balance : IERC20(Fungible.unwrap(self)).balanceOf(owner);
    }
}
