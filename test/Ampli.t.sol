// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {RiskConfigs, IRiskConfigs} from "../src/modules/RiskConfigs.sol";
import {Ampli, IRiskGovernor} from "../src/Ampli.sol";
import {IAmpli} from "../src/interfaces/IAmpli.sol";
import {Fungible, FungibleLibrary} from "../src/types/Fungible.sol";
import {NonFungible} from "../src/types/NonFungible.sol";
import {TestAmpli} from "./utils/TestAmpli.sol";
import {LockLibrary} from "../src/structs/Lock.sol";
import {TestERC721} from "./utils/TestERC721.sol";
import {TestNonFungibleOwner} from "./utils/TestNonFungibleOwner.sol";

contract AmpliTest is Test, Deployers, TestNonFungibleOwner {
    TestAmpli ampli;
    TestERC721 mockERC721;
    uint256 private lastMintedNftId = 1;

    function setUp() public {
        deployFreshManagerAndRouters();

        address hookAddress = address(
            uint160(
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG
                    | Hooks.AFTER_SWAP_FLAG
            )
        );

        RiskConfigs.RiskParams memory riskParams =
            RiskConfigs.RiskParams(IRiskConfigs.InterestMode.Normal, 1e8, 1e10, 9e17, 1e16);

        Ampli.ConstructorArgs memory args = Ampli.ConstructorArgs(
            manager, 500, 10, "Ampli v1 PED", "PEDv1", 18, IRiskGovernor(address(this)), riskParams
        );

        deployCodeTo("TestAmpli.sol", abi.encode(args), hookAddress);

        ampli = TestAmpli(hookAddress);
        mockERC721 = new TestERC721();
    }

    function test_openPosition_shouldOpenPositionAndEmitEvent() public {
        address owner = address(this); // change to fuzzy test?

        vm.expectEmit(false, true, false, true);
        emit IAmpli.PositionOpened(0, owner, address(0));

        vm.prank(owner);
        uint256 id = ampli.openPosition(address(this));

        assertEq(owner, ampli.ownerOf(id));
    }

    function test_openPosition_shouldReturnDiffIdEachTime() public {
        uint256 id1 = ampli.openPosition(address(this));
        uint256 id2 = ampli.openPosition(address(this));
        vm.prank(address(manager));
        uint256 id3 = ampli.openPosition(address(0));

        assertTrue(id1 != id2);
        assertTrue(id2 != id3);
        assertTrue(id3 != id1);
    }

    function test_closePosition_shouldClosePositionAndEmitEventIfCalledByOwner() public {
        uint256 id = ampli.openPosition(address(this));

        vm.expectEmit();
        emit IAmpli.PositionClosed(id);

        ampli.closePosition(id);

        assertEq(ampli.ownerOf(id), address(0));
    }

    function test_closePosition_shouldRevertIfNotCalledByOwner() public {
        vm.prank(address(manager));
        uint256 id = ampli.openPosition(address(0));

        vm.expectRevert(IAmpli.NotOwner.selector);
        ampli.closePosition(id);
    }

    function test_depositFungible_cannotDepositIntoNonExistsPosition() public {
        uint256 id = ampli.nextPositionId();

        vm.expectRevert(IAmpli.PositionDoesNotExist.selector);
        ampli.depositFungible(id, Fungible.wrap(address(0)), 10e18);
    }

    function testFuzz_depositFungible_shouldRevertIfNotEnoughFungibleRecieved(uint256 amount) public {
        vm.assume(amount < UINT256_MAX);

        uint256 id = ampli.openPosition(address(0));

        Fungible fungible = Fungible.wrap(address(ampli));

        if (amount != 0) {
            ampli.ft_mint(address(this), amount);
            fungible.transfer(address(ampli), amount);
        }

        vm.expectRevert(IAmpli.FungibleAmountNotRecieved.selector);
        ampli.depositFungible(id, fungible, amount + 1);
    }

    function testFuzz_depositFungible_shouldIncreaseFungibleValueCorrectly(uint256 amount) public {
        vm.assume(amount != 0);
        uint256 id = ampli.openPosition(address(0));

        ampli.ft_mint(address(this), amount);

        Fungible fungible = Fungible.wrap(address(ampli));
        fungible.transfer(address(ampli), amount);

        vm.expectEmit();
        emit IAmpli.FungibleDeposited(id, address(this), fungible, amount);

        ampli.depositFungible(id, fungible, amount);

        assertEq(amount, ampli.balanceOf(id, fungible));
        assertTrue(ampli.ft_isFungibleBalanced(fungible));
    }

    function test_depositFungible_shouldSupportNativeToken() public {
        Fungible fungible = FungibleLibrary.NATIVE;

        uint256 id = ampli.openPosition(address(0));
        uint256 amount = 10e18; // do not use testFuzz in case we spent all native token on address(this)

        vm.expectEmit();
        emit IAmpli.FungibleDeposited(id, address(this), fungible, amount);

        ampli.depositFungible{value: amount}(id, fungible, amount);

        assertEq(amount, ampli.balanceOf(id, fungible));
        assertTrue(ampli.ft_isFungibleBalanced(fungible));
    }

    function test_withdrawFungible_cannotInvokeOutsideUnlockCallback() public {
        uint256 id = ampli.openPosition(address(0));

        vm.expectRevert(LockLibrary.LockNotUnlocked.selector);
        ampli.withdrawFungible(id, FungibleLibrary.NATIVE, 1 ether, address(this));
    }

    function test_withdrawFungible_cannotWithdrawFromEmptyOrOthersPosition() public {
        vm.prank(address(manager));
        uint256 id = ampli.openPosition(address(0));

        // Simluate callback environment
        ampli.ft_unlock();

        vm.expectRevert(IAmpli.NotOwner.selector);
        ampli.withdrawFungible(id, FungibleLibrary.NATIVE, 1 ether, address(this));

        ampli.ft_lock();
    }

    function test_withdrawFungible_shouldRevertIfBalanceIsNotEnough() public {
        uint256 id = ampli.openPosition(address(0));
        Fungible fungible = Fungible.wrap(address(ampli));

        // empty balance
        ampli.ft_unlock();
        vm.expectRevert(IAmpli.FungibleBalanceInsufficient.selector);
        ampli.withdrawFungible(id, fungible, 1e18, address(this));
        ampli.ft_lock();

        uint256 amount = 10e18;
        ampli.ft_mint(address(this), amount);
        fungible.transfer(address(ampli), amount);
        ampli.depositFungible(id, fungible, amount);

        // balance insufficient
        ampli.ft_unlock();
        vm.expectRevert(IAmpli.FungibleBalanceInsufficient.selector);
        ampli.withdrawFungible(id, fungible, amount + 1e18, address(this));
        ampli.ft_lock();
    }

    function withdrawFungibleTestHelper(
        Fungible fungible,
        uint256 depositAmount,
        uint256 withdrawAmount,
        address recipient
    ) private {
        uint256 id = ampli.openPosition(address(0));

        if (fungible == FungibleLibrary.NATIVE) {
            ampli.depositFungible{value: depositAmount}(id, fungible, depositAmount);
        } else {
            fungible.transfer(address(ampli), depositAmount);
            ampli.depositFungible(id, fungible, depositAmount);
        }

        uint256 beforeAmount = fungible.balanceOf(recipient);

        ampli.ft_unlock();
        vm.expectEmit();
        emit IAmpli.FungibleWithdrawn(id, recipient, fungible, withdrawAmount);
        ampli.withdrawFungible(id, fungible, withdrawAmount, recipient);
        ampli.ft_lock();

        assertEq(ampli.balanceOf(id, fungible), depositAmount - withdrawAmount);
        assertEq(fungible.balanceOf(recipient), beforeAmount + withdrawAmount);
        assertTrue(ampli.ft_isFungibleBalanced(fungible));
    }

    function testFuzz_withdrawFungible_shouldDecreaseBalanceAndEmitEventCorrectly(uint256 deposit, uint256 withdraw)
        public
    {
        vm.assume(deposit >= withdraw);

        Fungible fungible = Fungible.wrap(address(ampli));
        ampli.ft_mint(address(this), deposit);

        withdrawFungibleTestHelper(fungible, deposit, withdraw, address(this));
    }

    function testFuzz_withdrawFungible_couldSetDifferentRecipient(uint256 deposit, uint256 withdraw) public {
        vm.assume(deposit >= withdraw);

        Fungible fungible = Fungible.wrap(address(ampli));
        ampli.ft_mint(address(this), deposit);

        withdrawFungibleTestHelper(fungible, deposit, withdraw, address(manager));
    }

    function test_withdrawFungible_shouldSupportNativeToken() public {
        Fungible fungible = FungibleLibrary.NATIVE;
        withdrawFungibleTestHelper(fungible, 1 ether, 1 ether, address(this));
    }

    function test_depositNonFungible_cannotDepositeIntoNonExistsPosition() public {
        NonFungible nf = NonFungible.wrap(address(mockERC721));
        uint256 nftId = ++lastMintedNftId;
        mockERC721.mint(address(ampli), nftId);

        uint256 id = ampli.nextPositionId();
        vm.expectRevert(IAmpli.PositionDoesNotExist.selector);
        ampli.depositNonFungible(id, nf, nftId);
    }

    function test_depositNonFugible_shouldRevertIfItemNotRecieved() public {
        NonFungible nf = NonFungible.wrap(address(mockERC721));
        mockERC721.mint(address(this), ++lastMintedNftId);

        uint256 id = ampli.openPosition(address(0));
        vm.expectRevert(IAmpli.NonFungibleItemNotRecieved.selector);
        ampli.depositNonFungible(id, nf, lastMintedNftId);
    }

    function test_depositNonFungible_cannotDepositeSameItemTwice() public {
        uint256 id = ampli.openPosition(address(0));

        NonFungible nf = NonFungible.wrap(address(mockERC721));
        mockERC721.mint(address(ampli), ++lastMintedNftId);

        ampli.depositNonFungible(id, nf, lastMintedNftId);

        vm.expectRevert(IAmpli.NonFungibleItemAlreadyDeposited.selector);
        ampli.depositNonFungible(id, nf, lastMintedNftId);
    }

    function test_depositNonFungible_shouldAddItemToPositionAndEmitEvent() public {
        uint256 id = ampli.openPosition(address(0));

        NonFungible nf = NonFungible.wrap(address(mockERC721));
        mockERC721.mint(address(ampli), ++lastMintedNftId);

        uint256 beforeBalance = ampli.itemsCountOf(id, nf);

        vm.expectEmit();
        emit IAmpli.NonFungibleDeposited(id, address(this), nf, lastMintedNftId);
        ampli.depositNonFungible(id, nf, lastMintedNftId);

        assertEq(beforeBalance + 1, ampli.itemsCountOf(id, nf));
        assertEq(id, ampli.positionOf(nf, lastMintedNftId));
    }

    function test_withdrawNonFungible_cannotWithdrawFromNonExistOrOthersPosition() public {
        NonFungible nf = NonFungible.wrap(address(mockERC721));
        uint256 id = ampli.nextPositionId();

        ampli.ft_unlock();

        vm.expectRevert(IAmpli.NotOwner.selector);
        ampli.withdrawNonFungible(id, nf, lastMintedNftId, address(this));

        vm.prank(address(manager));
        id = ampli.openPosition(address(0));

        vm.expectRevert(IAmpli.NotOwner.selector);
        ampli.withdrawNonFungible(id, nf, lastMintedNftId, address(this));

        ampli.ft_lock();
    }

    function test_withdrawNonFungible_shouldRevertIfItemNotExistsInPosition() public {
        NonFungible nf = NonFungible.wrap(address(mockERC721));
        uint256 id = ampli.openPosition(address(0));
        mockERC721.mint(address(this), ++lastMintedNftId);

        ampli.ft_unlock();
        vm.expectRevert(IAmpli.NonFungibleItemNotInPosition.selector);
        ampli.withdrawNonFungible(id, nf, lastMintedNftId, address(this));
        ampli.ft_lock();
    }

    function test_withdrawNonFungible_cannotInvokeWithoutLock() public {
        NonFungible nf = NonFungible.wrap(address(mockERC721));
        uint256 id = ampli.openPosition(address(0));

        mockERC721.mint(address(ampli), ++lastMintedNftId);
        ampli.depositNonFungible(id, nf, lastMintedNftId);

        vm.expectRevert(LockLibrary.LockNotUnlocked.selector);
        ampli.withdrawNonFungible(id, nf, lastMintedNftId, address(this));
    }

    function withdrawNonFungibleTestHelper(NonFungible nf, uint256 item, address recipient) private {
        uint256 id = ampli.openPosition(address(0));
        nf.transfer(address(ampli), item);
        ampli.depositNonFungible(id, nf, item);

        uint256 beforeBalance = ampli.itemsCountOf(id, nf);

        ampli.ft_unlock();
        vm.expectEmit();
        emit IAmpli.NonFungibleWithdrawn(id, recipient, nf, item);
        ampli.withdrawNonFungible(id, nf, item, recipient);
        ampli.ft_lock();

        assertEq(beforeBalance, ampli.itemsCountOf(id, nf) + 1);
        assertEq(0, ampli.positionOf(nf, lastMintedNftId));

        assertEq(recipient, nf.ownerOf(item));
    }

    function test_withdrawNonFungible_shouldWithdrawAndEmitEvent() public {
        NonFungible nf = NonFungible.wrap(address(mockERC721));
        mockERC721.mint(address(this), ++lastMintedNftId);
        withdrawNonFungibleTestHelper(nf, lastMintedNftId, address(this));
    }

    function test_withdrawNonFungible_couldWithdrawToDiffRecipient() public {
        NonFungible nf = NonFungible.wrap(address(mockERC721));
        TestNonFungibleOwner recipient = new TestNonFungibleOwner();

        mockERC721.mint(address(this), ++lastMintedNftId);

        withdrawNonFungibleTestHelper(nf, lastMintedNftId, address(recipient));
    }
}
