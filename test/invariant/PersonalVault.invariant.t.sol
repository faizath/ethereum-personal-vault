// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PersonalVault} from "../../src/PersonalVault.sol";
import {VaultHandler} from "./VaultHandler.sol";

/// @title PersonalVaultInvariantTest
/// @author Faiz A
/// @notice Stateful fuzzing: properties that must hold after any sequence of handler calls.
contract PersonalVaultInvariantTest is Test {
    uint256 internal constant START_TIME = 1_760_000_000;
    uint256 internal constant LOCK_DURATION = 1 days;
    uint256 internal constant STARTING_BALANCE = 1000 ether;
    uint256 internal constant DEPOSITOR_COUNT = 3;

    PersonalVault internal vault;
    VaultHandler internal handler;
    address internal owner = makeAddr("owner");
    uint256 internal initialUnlockTime;

    function setUp() public {
        vm.warp(START_TIME);
        initialUnlockTime = START_TIME + LOCK_DURATION;

        vm.prank(owner);
        vault = new PersonalVault(initialUnlockTime);
        vm.deal(owner, STARTING_BALANCE);

        address[] memory depositors = new address[](DEPOSITOR_COUNT);
        for (uint256 i; i < DEPOSITOR_COUNT; ++i) {
            depositors[i] = makeAddr(string.concat("depositor", vm.toString(i)));
            vm.deal(depositors[i], STARTING_BALANCE);
        }

        handler = new VaultHandler(vault, depositors);

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = VaultHandler.deposit.selector;
        selectors[1] = VaultHandler.withdraw.selector;
        selectors[2] = VaultHandler.withdrawAsNonOwner.selector;
        selectors[3] = VaultHandler.extendLock.selector;
        selectors[4] = VaultHandler.extendLockToEarlierTime.selector;
        selectors[5] = VaultHandler.extendLockAsNonOwner.selector;
        selectors[6] = VaultHandler.warp.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// @notice The lock can only ever move forward in time.
    function invariant_UnlockTimeNeverDecreases() public view {
        assertFalse(handler.ghostUnlockTimeDecreased());
        assertGe(vault.unlockTime(), initialUnlockTime);
    }

    /// @notice No withdrawal ever succeeds while `block.timestamp < unlockTime`.
    function invariant_FundsNeverLeaveBeforeUnlock() public view {
        assertEq(handler.ghostEarlyWithdrawals(), 0);
    }

    /// @notice Non-owners can never withdraw or extend the lock.
    function invariant_OnlyOwnerCanWithdrawOrExtend() public view {
        assertEq(handler.ghostUnauthorizedSuccesses(), 0);
    }

    /// @notice Attempts to keep or shorten the unlock time always revert.
    function invariant_LockCanNeverBeShortened() public view {
        assertEq(handler.ghostShortenedLocks(), 0);
    }

    /// @notice Liveness: once unlocked, an owner withdrawal of a non-empty vault always succeeds.
    function invariant_OwnerCanAlwaysWithdrawWhenUnlocked() public view {
        assertEq(handler.ghostUnexpectedWithdrawFailures(), 0);
    }

    /// @notice The vault holds exactly what was deposited minus what was withdrawn.
    function invariant_BalanceMatchesAccounting() public view {
        assertEq(address(vault).balance, handler.ghostTotalDeposited() - handler.ghostTotalWithdrawn());
    }

    /// @notice Only the owner ever receives ETH from the vault; other depositors only ever pay in.
    function invariant_OnlyOwnerReceivesFunds() public view {
        assertEq(
            owner.balance, STARTING_BALANCE - handler.ghostOwnerDeposited() + handler.ghostTotalWithdrawn(), "owner"
        );

        address[] memory depositors = handler.nonOwnerDepositors();
        uint256 depositorsTotal;
        for (uint256 i; i < depositors.length; ++i) {
            depositorsTotal += depositors[i].balance;
        }
        uint256 nonOwnerDeposited = handler.ghostTotalDeposited() - handler.ghostOwnerDeposited();
        assertEq(depositorsTotal, STARTING_BALANCE * depositors.length - nonOwnerDeposited, "depositors");
    }
}
