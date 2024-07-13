// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {NonFungibleTokenReceiver} from "../../src/modules/NonFungibleTokenReceiver.sol";
import {NonFungible} from "../../src/types/NonFungible.sol";

contract TestNonFungibleOwner is NonFungibleTokenReceiver {
    function transfer(NonFungible nonFungible, address to, uint256 item) external {
        nonFungible.transfer(to, item);
    }
}
