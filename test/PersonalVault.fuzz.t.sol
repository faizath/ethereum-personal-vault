// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PersonalVault} from "../src/PersonalVault.sol";
import {VaultTestBase} from "./utils/VaultTestBase.sol";

/// @title PersonalVaultFuzzTest
/// @author Faiz A
/// @notice Property-based tests over unlock times, deposit amounts, callers and timestamps.
contract PersonalVaultFuzzTest is VaultTestBase {
    uint256 internal constant MAX_DEPOSIT = 1_000_000 ether;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Constructor_AcceptsAnyFutureUnlockTime(uint256 time) public {
        time = bound(time, block.timestamp + 1, type(uint256).max);

        PersonalVault v = new PersonalVault(time);

        assertEq(v.unlockTime(), time);
        assertEq(v.owner(), address(this));
    }

    function testFuzz_Constructor_RevertsOnNonFutureUnlockTime(uint256 time) public {
        time = bound(time, 0, block.timestamp);

        vm.expectRevert(PersonalVault.InvalidUnlockTime.selector);
        new PersonalVault(time);
    }

    function testFuzz_Constructor_WithValue(uint256 amount) public {
        amount = bound(amount, 1, MAX_DEPOSIT);
        vm.deal(owner, amount);

        vm.expectEmit(true, false, false, true);
        emit PersonalVault.Deposit(owner, amount);
        vm.prank(owner);
        PersonalVault v = new PersonalVault{value: amount}(unlockTime);

        assertEq(address(v).balance, amount);
    }

    /*//////////////////////////////////////////////////////////////
                                DEPOSIT
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Deposit_AnySenderAnyAmount(address sender, uint256 amount) public {
        assumeNotForgeAddress(sender);
        assumeNotPrecompile(sender);
        vm.assume(sender != address(vault));
        amount = bound(amount, 1, MAX_DEPOSIT);
        vm.deal(sender, amount);

        vm.expectEmit(true, false, false, true, address(vault));
        emit PersonalVault.Deposit(sender, amount);
        _depositAs(sender, amount);

        assertEq(vault.balance(), amount);
    }

    function testFuzz_Deposit_ViaReceive(uint256 amount) public {
        amount = bound(amount, 1, MAX_DEPOSIT);
        vm.deal(alice, amount);

        vm.prank(alice);
        (bool ok,) = address(vault).call{value: amount}("");

        assertTrue(ok);
        assertEq(vault.balance(), amount);
    }

    function testFuzz_Deposit_Accumulates(uint256 first, uint256 second) public {
        first = bound(first, 1, MAX_DEPOSIT);
        second = bound(second, 1, MAX_DEPOSIT);
        vm.deal(alice, first);
        vm.deal(bob, second);

        _depositAs(alice, first);
        _depositAs(bob, second);

        assertEq(vault.balance(), first + second);
    }

    /*//////////////////////////////////////////////////////////////
                                WITHDRAW
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Withdraw_RevertsAnyTimeBeforeUnlock(uint256 warpTo, uint256 amount) public {
        warpTo = bound(warpTo, block.timestamp, unlockTime - 1);
        amount = bound(amount, 1, STARTING_BALANCE);
        _depositAs(owner, amount);
        vm.warp(warpTo);

        vm.expectRevert(PersonalVault.FundsLocked.selector);
        vm.prank(owner);
        vault.withdraw();

        assertEq(vault.balance(), amount);
    }

    function testFuzz_Withdraw_SucceedsAnyTimeAfterUnlock(uint256 warpTo, uint256 amount) public {
        warpTo = bound(warpTo, unlockTime, type(uint64).max);
        amount = bound(amount, 1, STARTING_BALANCE);
        _depositAs(alice, amount);
        vm.warp(warpTo);

        vm.expectEmit(false, false, false, true, address(vault));
        emit PersonalVault.Withdrawal(amount, warpTo);
        vm.prank(owner);
        vault.withdraw();

        assertEq(vault.balance(), 0);
        assertEq(owner.balance, STARTING_BALANCE + amount);
    }

    function testFuzz_Withdraw_RevertsForNonOwner(address caller, uint256 warpTo) public {
        vm.assume(caller != owner);
        warpTo = bound(warpTo, block.timestamp, type(uint64).max);
        _depositAs(alice, DEPOSIT_AMOUNT);
        vm.warp(warpTo);

        vm.expectRevert(PersonalVault.NotOwner.selector);
        vm.prank(caller);
        vault.withdraw();

        assertEq(vault.balance(), DEPOSIT_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                              EXTEND LOCK
    //////////////////////////////////////////////////////////////*/

    function testFuzz_ExtendLock_AcceptsAnyLaterTime(uint256 newTime) public {
        newTime = bound(newTime, unlockTime + 1, type(uint256).max);

        vm.expectEmit(false, false, false, true, address(vault));
        emit PersonalVault.LockExtended(newTime);
        vm.prank(owner);
        vault.extendLock(newTime);

        assertEq(vault.unlockTime(), newTime);
    }

    function testFuzz_ExtendLock_RevertsWhenNotLater(uint256 newTime) public {
        newTime = bound(newTime, 0, unlockTime);

        vm.expectRevert(PersonalVault.InvalidUnlockTime.selector);
        vm.prank(owner);
        vault.extendLock(newTime);

        assertEq(vault.unlockTime(), unlockTime);
    }

    function testFuzz_ExtendLock_AfterUnlock_RequiresFutureTime(uint256 warpTo, uint256 newTime) public {
        warpTo = bound(warpTo, unlockTime, type(uint64).max);
        vm.warp(warpTo);
        newTime = bound(newTime, 0, type(uint128).max);

        vm.prank(owner);
        if (newTime <= warpTo) {
            vm.expectRevert(PersonalVault.InvalidUnlockTime.selector);
            vault.extendLock(newTime);
            assertEq(vault.unlockTime(), unlockTime);
        } else {
            vault.extendLock(newTime);
            assertEq(vault.unlockTime(), newTime);
            assertFalse(vault.isUnlocked());
        }
    }

    function testFuzz_ExtendLock_RevertsForNonOwner(address caller, uint256 newTime) public {
        vm.assume(caller != owner);
        newTime = bound(newTime, unlockTime + 1, type(uint256).max);

        vm.expectRevert(PersonalVault.NotOwner.selector);
        vm.prank(caller);
        vault.extendLock(newTime);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Views_AreConsistentWithUnlockTime(uint256 warpTo) public {
        warpTo = bound(warpTo, block.timestamp, type(uint64).max);
        vm.warp(warpTo);

        bool unlocked = vault.isUnlocked();
        uint256 remaining = vault.timeUntilUnlock();

        assertEq(unlocked, warpTo >= unlockTime);
        assertEq(remaining, unlocked ? 0 : unlockTime - warpTo);
        assertEq(remaining == 0, unlocked);
    }
}
