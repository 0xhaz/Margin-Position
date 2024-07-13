// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Fungible, FungibleLibrary} from "../../src/types/Fungible.sol";
import {NonFungible} from "../../src/types/NonFungible.sol";
import {Ampli} from "../../src/Ampli.sol";
import {Position, NonFungibleAsset} from "../../src/structs/Position.sol";

contract TestAmpli is Ampli {
    constructor(Ampli.ConstructorArgs memory args) Ampli(args) {}

    function ft_unlock() public {
        s_lock.unlock();
    }

    function ft_lock() public {
        s_lock.checkInAll();
        s_lock.lock();
    }

    function ft_mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function ft_isFungibleBalanced(Fungible fungible) public view returns (bool) {
        if (fungible == FungibleLibrary.NATIVE) {
            uint256 amount = globalBalanceOf(fungible);
            return amount + surplus() == fungible.balanceOf(address(this));
        }

        return globalBalanceOf(fungible) == fungible.balanceOf(address(this));
    }
}
