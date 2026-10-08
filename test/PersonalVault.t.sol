// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {PersonalVault} from "../src/PersonalVault.sol";
import {VaultTestBase} from "./utils/VaultTestBase.sol";
import {RejectingOwner} from "./mocks/RejectingOwner.sol";
import {ReentrantOwner} from "./mocks/ReentrantOwner.sol";

/// @title PersonalVaultTest
/// @author Faiz A
/// @notice Unit tests covering every function, revert path and event of {PersonalVault}.
contract PersonalVaultTest is VaultTestBase {
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function test_Constructor_SetsOwnerAndUnlockTime() public view {
        assertEq(vault.owner(), owner);
        assertEq(vault.unlockTime(), unlockTime);
        assertEq(vault.balance(), 0);
    }

    function test_Constructor_WithValue_HoldsFundsAndEmitsDeposit() public {
        vm.expectEmit(true, false, false, true);
        emit PersonalVault.Deposit(owner, DEPOSIT_AMOUNT);

        vm.prank(owner);
        PersonalVault funded = new PersonalVault{value: DEPOSIT_AMOUNT}(unlockTime);

        assertEq(address(funded).balance, DEPOSIT_AMOUNT);
        assertEq(funded.owner(), owner);
    }

    function test_Constructor_WithoutValue_EmitsNoEvent() public {
        vm.recordLogs();
        vm.prank(owner);
        new PersonalVault(unlockTime);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    function test_Constructor_AcceptsUnlockTimeOneSecondAhead() public {
        PersonalVault v = new PersonalVault(block.timestamp + 1);
        assertEq(v.unlockTime(), block.timestamp + 1);
    }

    function test_Constructor_RevertsWhen_UnlockTimeIsNow() public {
        vm.expectRevert(PersonalVault.InvalidUnlockTime.selector);
        new PersonalVault(block.timestamp);
    }

    function test_Constructor_RevertsWhen_UnlockTimeInPast() public {
        vm.expectRevert(PersonalVault.InvalidUnlockTime.selector);
        new PersonalVault(block.timestamp - 1);
    }

    function test_Constructor_RevertsWhen_UnlockTimeIsZero() public {
        vm.expectRevert(PersonalVault.InvalidUnlockTime.selector);
        new PersonalVault(0);
    }

    /*//////////////////////////////////////////////////////////////
                                DEPOSIT
    //////////////////////////////////////////////////////////////*/

    function test_Deposit_ByOwner_EmitsEventAndIncreasesBalance() public {
        vm.expectEmit(true, false, false, true, address(vault));
        emit PersonalVault.Deposit(owner, DEPOSIT_AMOUNT);

        _depositAs(owner, DEPOSIT_AMOUNT);

        assertEq(vault.balance(), DEPOSIT_AMOUNT);
        assertEq(owner.balance, STARTING_BALANCE - DEPOSIT_AMOUNT);
    }

    function test_Deposit_ByNonOwner_IsAcceptedAndLogsSender() public {
        vm.expectEmit(true, false, false, true, address(vault));
        emit PersonalVault.Deposit(alice, DEPOSIT_AMOUNT);

        _depositAs(alice, DEPOSIT_AMOUNT);

        assertEq(vault.balance(), DEPOSIT_AMOUNT);
    }

    function test_Deposit_MultipleDepositsAccumulate() public {
        _depositAs(owner, 1 ether);
        _depositAs(alice, 2 ether);
        _depositAs(bob, 0.5 ether);

        assertEq(vault.balance(), 3.5 ether);
    }

    function test_Deposit_AllowedAfterUnlock() public {
        _warpToUnlock();
        _depositAs(alice, DEPOSIT_AMOUNT);
        assertEq(vault.balance(), DEPOSIT_AMOUNT);
    }

    function test_Deposit_RevertsWhen_ZeroValue() public {
        vm.expectRevert(PersonalVault.ZeroDeposit.selector);
        vm.prank(owner);
        vault.deposit{value: 0}();
    }

    /*//////////////////////////////////////////////////////////////
                           RECEIVE / FALLBACK
    //////////////////////////////////////////////////////////////*/

    function test_Receive_PlainTransferIsDeposit() public {
        vm.expectEmit(true, false, false, true, address(vault));
        emit PersonalVault.Deposit(alice, DEPOSIT_AMOUNT);

        vm.prank(alice);
        (bool ok,) = address(vault).call{value: DEPOSIT_AMOUNT}("");

        assertTrue(ok);
        assertEq(vault.balance(), DEPOSIT_AMOUNT);
    }

    function test_Receive_RevertsWhen_ZeroValue() public {
        vm.prank(alice);
        (bool ok, bytes memory reason) = address(vault).call("");

        assertFalse(ok);
        assertEq(reason, abi.encodeWithSelector(PersonalVault.ZeroDeposit.selector));
    }

    function test_UnknownCalldata_Reverts() public {
        vm.prank(alice);
        (bool ok,) = address(vault).call{value: DEPOSIT_AMOUNT}(abi.encodeWithSignature("notAFunction()"));

        assertFalse(ok);
        assertEq(vault.balance(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                                WITHDRAW
    //////////////////////////////////////////////////////////////*/

    function test_Withdraw_AfterUnlock_SendsEntireBalanceAndEmits() public {
        _depositAs(owner, DEPOSIT_AMOUNT);
        _depositAs(alice, 2 ether);
        vm.warp(unlockTime + 1 days);

        vm.expectEmit(false, false, false, true, address(vault));
        emit PersonalVault.Withdrawal(3 ether, block.timestamp);

        vm.prank(owner);
        vault.withdraw();

        assertEq(vault.balance(), 0);
        assertEq(owner.balance, STARTING_BALANCE - DEPOSIT_AMOUNT + 3 ether);
    }

    function test_Withdraw_SucceedsAtExactUnlockTime() public {
        _depositAs(owner, DEPOSIT_AMOUNT);
        vm.warp(unlockTime);

        vm.prank(owner);
        vault.withdraw();

        assertEq(vault.balance(), 0);
        assertEq(owner.balance, STARTING_BALANCE);
    }

    function test_Withdraw_RevertsWhen_Locked() public {
        _depositAs(owner, DEPOSIT_AMOUNT);

        vm.expectRevert(PersonalVault.FundsLocked.selector);
        vm.prank(owner);
        vault.withdraw();
    }

    function test_Withdraw_RevertsWhen_OneSecondBeforeUnlock() public {
        _depositAs(owner, DEPOSIT_AMOUNT);
        vm.warp(unlockTime - 1);

        vm.expectRevert(PersonalVault.FundsLocked.selector);
        vm.prank(owner);
        vault.withdraw();
    }

    function test_Withdraw_RevertsWhen_LockedEvenIfEmpty() public {
        vm.expectRevert(PersonalVault.FundsLocked.selector);
        vm.prank(owner);
        vault.withdraw();
    }

    function test_Withdraw_RevertsWhen_NotOwnerAfterUnlock() public {
        _depositAs(alice, DEPOSIT_AMOUNT);
        _warpToUnlock();

        vm.expectRevert(PersonalVault.NotOwner.selector);
        vm.prank(alice);
        vault.withdraw();

        assertEq(vault.balance(), DEPOSIT_AMOUNT);
    }

    function test_Withdraw_RevertsWhen_NotOwnerWhileLocked() public {
        _depositAs(alice, DEPOSIT_AMOUNT);

        vm.expectRevert(PersonalVault.NotOwner.selector);
        vm.prank(alice);
        vault.withdraw();
    }

    function test_Withdraw_RevertsWhen_NoBalance() public {
        _warpToUnlock();

        vm.expectRevert(PersonalVault.NoBalance.selector);
        vm.prank(owner);
        vault.withdraw();
    }

    function test_Withdraw_RevertsWhen_OwnerRejectsEther() public {
        RejectingOwner rejecting = new RejectingOwner(unlockTime);
        PersonalVault rejectingVault = rejecting.vault();
        vm.prank(alice);
        rejectingVault.deposit{value: DEPOSIT_AMOUNT}();
        vm.warp(unlockTime);

        vm.expectRevert(PersonalVault.TransferFailed.selector);
        rejecting.withdraw();

        assertEq(address(rejectingVault).balance, DEPOSIT_AMOUNT);
    }

    function test_Withdraw_ReentrantOwnerCannotDoubleWithdraw() public {
        ReentrantOwner attacker = new ReentrantOwner(unlockTime);
        PersonalVault attackedVault = attacker.vault();
        vm.prank(alice);
        attackedVault.deposit{value: DEPOSIT_AMOUNT}();
        vm.warp(unlockTime);

        vm.recordLogs();
        attacker.attack();

        assertTrue(attacker.reentryAttempted());
        assertFalse(attacker.reentrySucceeded());
        assertEq(attacker.reentryRevertData(), abi.encodeWithSelector(PersonalVault.NoBalance.selector));
        assertEq(address(attacker).balance, DEPOSIT_AMOUNT, "attacker received more than the balance");
        assertEq(address(attackedVault).balance, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "exactly one Withdrawal event");
        assertEq(logs[0].topics[0], PersonalVault.Withdrawal.selector);
    }

    function test_Withdraw_IncludesForceSentEther() public {
        _depositAs(owner, DEPOSIT_AMOUNT);
        // Simulates ETH arriving without calling the vault (selfdestruct / coinbase rewards).
        vm.deal(address(vault), address(vault).balance + 0.5 ether);
        _warpToUnlock();

        vm.prank(owner);
        vault.withdraw();

        assertEq(owner.balance, STARTING_BALANCE + 0.5 ether);
    }

    function test_Withdraw_CanWithdrawAgainAfterNewDeposit() public {
        _depositAs(owner, DEPOSIT_AMOUNT);
        _warpToUnlock();
        vm.prank(owner);
        vault.withdraw();

        _depositAs(alice, 2 ether);
        vm.prank(owner);
        vault.withdraw();

        assertEq(owner.balance, STARTING_BALANCE + 2 ether);
    }

    /*//////////////////////////////////////////////////////////////
                              EXTEND LOCK
    //////////////////////////////////////////////////////////////*/

    function test_ExtendLock_UpdatesUnlockTimeAndEmits() public {
        uint256 newTime = unlockTime + 1 days;

        vm.expectEmit(false, false, false, true, address(vault));
        emit PersonalVault.LockExtended(newTime);

        vm.prank(owner);
        vault.extendLock(newTime);

        assertEq(vault.unlockTime(), newTime);
    }

    function test_ExtendLock_ByOneSecond() public {
        vm.prank(owner);
        vault.extendLock(unlockTime + 1);
        assertEq(vault.unlockTime(), unlockTime + 1);
    }

    function test_ExtendLock_CanBeExtendedRepeatedly() public {
        vm.startPrank(owner);
        vault.extendLock(unlockTime + 1 hours);
        vault.extendLock(unlockTime + 1 days);
        vault.extendLock(unlockTime + 30 days);
        vm.stopPrank();

        assertEq(vault.unlockTime(), unlockTime + 30 days);
    }

    function test_ExtendLock_BlocksWithdrawUntilNewTime() public {
        _depositAs(owner, DEPOSIT_AMOUNT);
        uint256 newTime = unlockTime + 1 hours;
        vm.prank(owner);
        vault.extendLock(newTime);

        vm.warp(unlockTime);
        vm.expectRevert(PersonalVault.FundsLocked.selector);
        vm.prank(owner);
        vault.withdraw();

        vm.warp(newTime);
        vm.prank(owner);
        vault.withdraw();
        assertEq(vault.balance(), 0);
    }

    function test_ExtendLock_RelocksAnUnlockedVault() public {
        vm.warp(unlockTime + 1 days);
        assertTrue(vault.isUnlocked());

        uint256 newTime = block.timestamp + 1 hours;
        vm.prank(owner);
        vault.extendLock(newTime);

        assertFalse(vault.isUnlocked());
        assertEq(vault.unlockTime(), newTime);
    }

    function test_ExtendLock_RevertsWhen_SameTime() public {
        vm.expectRevert(PersonalVault.InvalidUnlockTime.selector);
        vm.prank(owner);
        vault.extendLock(unlockTime);
    }

    function test_ExtendLock_RevertsWhen_Shortened() public {
        vm.expectRevert(PersonalVault.InvalidUnlockTime.selector);
        vm.prank(owner);
        vault.extendLock(unlockTime - 1);
    }

    function test_ExtendLock_RevertsWhen_LaterThanUnlockButAlreadyPast() public {
        vm.warp(unlockTime + 1 days);

        vm.expectRevert(PersonalVault.InvalidUnlockTime.selector);
        vm.prank(owner);
        vault.extendLock(unlockTime + 1 hours);
    }

    function test_ExtendLock_RevertsWhen_EqualToNowAfterUnlock() public {
        vm.warp(unlockTime + 1 days);

        vm.expectRevert(PersonalVault.InvalidUnlockTime.selector);
        vm.prank(owner);
        vault.extendLock(block.timestamp);
    }

    function test_ExtendLock_RevertsWhen_NotOwner() public {
        vm.expectRevert(PersonalVault.NotOwner.selector);
        vm.prank(alice);
        vault.extendLock(unlockTime + 1 days);

        assertEq(vault.unlockTime(), unlockTime);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    function test_IsUnlocked_FlipsExactlyAtUnlockTime() public {
        assertFalse(vault.isUnlocked());
        vm.warp(unlockTime - 1);
        assertFalse(vault.isUnlocked());
        vm.warp(unlockTime);
        assertTrue(vault.isUnlocked());
    }

    function test_TimeUntilUnlock_CountsDownToZero() public {
        assertEq(vault.timeUntilUnlock(), LOCK_DURATION);
        vm.warp(unlockTime - 1);
        assertEq(vault.timeUntilUnlock(), 1);
        vm.warp(unlockTime);
        assertEq(vault.timeUntilUnlock(), 0);
        vm.warp(unlockTime + 1 days);
        assertEq(vault.timeUntilUnlock(), 0);
    }

    function test_Balance_MatchesNativeBalance() public {
        _depositAs(alice, DEPOSIT_AMOUNT);
        assertEq(vault.balance(), address(vault).balance);
    }
}
