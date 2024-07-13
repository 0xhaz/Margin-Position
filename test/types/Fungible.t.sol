// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Fungible, FungibleLibrary} from "src/types/Fungible.sol";
import {TestERC20} from "test/utils/TestERC20.sol";
import {TestFungibleOwner} from "test/utils/TestFungibleOwner.sol";

contract FungibleTest is Test {
    TestFungibleOwner immutable owner1 = new TestFungibleOwner();
    TestFungibleOwner immutable owner2 = new TestFungibleOwner();

    TestERC20 immutable testERC20 = new TestERC20();
    Fungible immutable nativeFungible = Fungible.wrap(address(0));
    Fungible immutable erc20Fungible = Fungible.wrap(address(testERC20));

    function testFuzz_transferNative(uint256 initialAmount, uint256 transferAmount) public {
        initialAmount = bound(initialAmount, 0, type(uint256).max - 1);
        vm.deal(address(owner1), initialAmount);

        transferAmount = bound(transferAmount, 0, initialAmount);
        owner1.transfer(nativeFungible, address(owner2), transferAmount);

        assertEq(address(owner1).balance, initialAmount - transferAmount);
        assertEq(address(owner2).balance, transferAmount);

        transferAmount = address(owner1).balance + 1;
        vm.expectRevert(FungibleLibrary.FungibleTransferFailed.selector);
        owner1.transfer(nativeFungible, address(owner2), transferAmount);
    }

    function testFuzz_transferERC20(uint256 initialAmount, uint256 transferAmount) public {
        initialAmount = bound(initialAmount, 0, type(uint256).max - 1);
        testERC20.mint(address(owner1), initialAmount);

        transferAmount = bound(transferAmount, 0, initialAmount);
        owner1.transfer(erc20Fungible, address(owner2), transferAmount);

        assertEq(testERC20.balanceOf(address(owner1)), initialAmount - transferAmount);
        assertEq(testERC20.balanceOf(address(owner2)), transferAmount);

        transferAmount = testERC20.balanceOf(address(owner1)) + 1;
        vm.expectRevert(FungibleLibrary.FungibleTransferFailed.selector);
        owner1.transfer(erc20Fungible, address(owner2), transferAmount);
    }

    function testFuzz_BalanceOfNative(uint256 initialAmount) public {
        vm.deal(address(owner1), initialAmount);

        assertEq(nativeFungible.balanceOf(address(owner1)), address(owner1).balance);
        assertEq(nativeFungible.balanceOf(address(owner2)), address(owner2).balance);
    }

    function testFuzz_BalanceOfERC20(uint256 initialAmount) public {
        testERC20.mint(address(owner1), initialAmount);

        assertEq(erc20Fungible.balanceOf(address(owner1)), testERC20.balanceOf(address(owner1)));
        assertEq(erc20Fungible.balanceOf(address(owner2)), testERC20.balanceOf(address(owner2)));
    }

    function testFuzz_equals(address a, address b) public pure {
        assertEq(a == b, Fungible.wrap(a) == Fungible.wrap(b));
    }
}
