// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Fungible} from "../../src/types/Fungible.sol";

contract TestFungibleOwner {
    function transfer(Fungible fungible, address to, uint256 amount) external {
        fungible.transfer(to, amount);
    }

    receive() external payable {}
}
