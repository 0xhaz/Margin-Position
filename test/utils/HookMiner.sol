// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Hooks} from "v4-core/libraries/Hooks.sol";

library HookMiner {
    function findSalt(address deployer, uint160 flags, bytes memory creationCode, bytes memory params)
        external
        pure
        returns (address address_, bytes32 salt)
    {
        bytes32 creationHash = keccak256(abi.encodePacked(creationCode, params));

        for (uint256 i = 0;; i++) {
            address_ = address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xFF), deployer, i, creationHash)))));

            if (uint160(address_) & Hooks.ALL_HOOK_MASK == flags) {
                return (address_, bytes32(i));
            }
        }
    }
}
