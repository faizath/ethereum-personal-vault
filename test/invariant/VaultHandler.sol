// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {PersonalVault} from "../../src/PersonalVault.sol";

/// @title VaultHandler
/// @author Faiz A
/// @notice Drives {PersonalVault} through random sequences of deposits, withdrawals, lock extensions and time
///         jumps, while recording ghost variables that the invariant suite checks after every call.
/// @dev Calls that are expected to revert (early withdrawals, unauthorized calls, shortened locks) are wrapped
///      in try/catch, so a *successful* call on those paths is recorded as a violation instead of being hidden.
contract VaultHandler is CommonBase, StdCheats, StdUtils {
    uint256 internal constant MAX_DEPOSIT = 10 ether;
    uint256 internal constant MAX_WARP = 7 days;
    /// @dev Kept close to MAX_WARP so runs regularly reach the unlocked state instead of staying locked forever.
    uint256 internal constant MAX_EXTENSION = 3 days;

    PersonalVault public immutable vault;
    address public immutable owner;
    address[] internal depositors;

    /// @dev Invariant runs don't reliably persist `vm.warp` between calls, so time is tracked explicitly.
    uint256 public currentTime;

    uint256 public ghostTotalDeposited;
    uint256 public ghostOwnerDeposited;
    uint256 public ghostTotalWithdrawn;
    uint256 public ghostLastUnlockTime;

    uint256 public ghostEarlyWithdrawals;
    uint256 public ghostUnauthorizedSuccesses;
    uint256 public ghostShortenedLocks;
    uint256 public ghostUnexpectedWithdrawFailures;
    bool public ghostUnlockTimeDecreased;

    modifier useCurrentTime() {
        vm.warp(currentTime);
        _;
        _trackUnlockTime();
    }

    constructor(PersonalVault vault_, address[] memory depositors_) {
        vault = vault_;
        owner = vault_.owner();
        depositors = depositors_;
        currentTime = block.timestamp;
        ghostLastUnlockTime = vault_.unlockTime();
    }

    /// @notice Deposit from a random actor (owner included), either via {deposit} or a plain transfer.
    function deposit(uint256 actorSeed, uint256 amount, bool viaReceive) external useCurrentTime {
        address actor = _anyActor(actorSeed);
        amount = bound(amount, 0, _min(actor.balance, MAX_DEPOSIT));
        if (amount == 0) return;

        vm.prank(actor);
        if (viaReceive) {
            (bool ok,) = address(vault).call{value: amount}("");
            require(ok, "receive deposit failed");
        } else {
            vault.deposit{value: amount}();
        }

        ghostTotalDeposited += amount;
        if (actor == owner) ghostOwnerDeposited += amount;
    }

    /// @notice Owner withdrawal at whatever the current time is; must succeed iff unlocked with a balance.
    function withdraw() external useCurrentTime {
        bool locked = block.timestamp < vault.unlockTime();
        uint256 amount = address(vault).balance;

        vm.prank(owner);
        try vault.withdraw() {
            if (locked) ghostEarlyWithdrawals++;
            ghostTotalWithdrawn += amount;
        } catch {
            if (!locked && amount > 0) ghostUnexpectedWithdrawFailures++;
        }
    }

    /// @notice A non-owner attempts to withdraw; must always revert.
    function withdrawAsNonOwner(uint256 actorSeed) external useCurrentTime {
        vm.prank(_nonOwner(actorSeed));
        try vault.withdraw() {
            ghostUnauthorizedSuccesses++;
        } catch {}
    }

    /// @notice Owner extends the lock to a valid later time; must always succeed.
    function extendLock(uint256 extension) external useCurrentTime {
        extension = bound(extension, 1, MAX_EXTENSION);
        uint256 base = _max(vault.unlockTime(), block.timestamp);

        vm.prank(owner);
        vault.extendLock(base + extension);
    }

    /// @notice Owner tries to set an unlock time that is not later than the current one; must always revert.
    function extendLockToEarlierTime(uint256 newTime) external useCurrentTime {
        newTime = bound(newTime, 0, vault.unlockTime());

        vm.prank(owner);
        try vault.extendLock(newTime) {
            ghostShortenedLocks++;
        } catch {}
    }

    /// @notice A non-owner attempts to extend the lock; must always revert.
    function extendLockAsNonOwner(uint256 actorSeed, uint256 newTime) external useCurrentTime {
        newTime = bound(newTime, vault.unlockTime() + 1, vault.unlockTime() + MAX_EXTENSION);

        vm.prank(_nonOwner(actorSeed));
        try vault.extendLock(newTime) {
            ghostUnauthorizedSuccesses++;
        } catch {}
    }

    /// @notice Moves time forward by up to a week.
    function warp(uint256 secondsForward) external {
        currentTime += bound(secondsForward, 0, MAX_WARP);
        vm.warp(currentTime);
    }

    /// @notice All non-owner actors, for balance-conservation checks.
    function nonOwnerDepositors() external view returns (address[] memory) {
        return depositors;
    }

    function _trackUnlockTime() internal {
        uint256 current = vault.unlockTime();
        if (current < ghostLastUnlockTime) ghostUnlockTimeDecreased = true;
        ghostLastUnlockTime = current;
    }

    /// @dev Index `depositors.length` maps to the owner, so the owner is one of the possible actors.
    function _anyActor(uint256 seed) internal view returns (address) {
        uint256 index = seed % (depositors.length + 1);
        return index == depositors.length ? owner : depositors[index];
    }

    function _nonOwner(uint256 seed) internal view returns (address) {
        return depositors[seed % depositors.length];
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}
