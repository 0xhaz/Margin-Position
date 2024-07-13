// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {MockERC721} from "forge-std/mocks/MockERC721.sol";

contract TestERC721 is MockERC721 {
    function mint(address to, uint256 id) external {
        _mint(to, id);
    }

    function burn(uint256 id) external {
        _burn(id);
    }
}
