// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PersonalVault} from "../../src/PersonalVault.sol";

/// @title ReentrantOwner
/// @author Faiz A
/// @notice Test double: a malicious owner contract that tries to call {PersonalVault.withdraw} again from inside
///         its `receive` hook, swallowing the nested revert so the outer withdrawal can still succeed.
contract ReentrantOwner {
    /// @notice The vault deployed (and therefore owned) by this contract.
    PersonalVault public immutable vault;

    /// @notice Whether `receive` has already tried to re-enter.
    bool public reentryAttempted;

    /// @notice Whether the nested {PersonalVault.withdraw} call succeeded (it must not).
    bool public reentrySucceeded;

    /// @notice Revert data returned by the nested {PersonalVault.withdraw} call.
    bytes public reentryRevertData;

    /// @param unlockTime Unlock time forwarded to the vault constructor.
    constructor(uint256 unlockTime) {
        vault = new PersonalVault(unlockTime);
    }

    /// @notice Starts the attack by withdrawing as the owner.
    function attack() external {
        vault.withdraw();
    }

    /// @notice Re-enters {PersonalVault.withdraw} once while the first payout is in flight.
    receive() external payable {
        if (reentryAttempted) return;
        reentryAttempted = true;
        try vault.withdraw() {
            reentrySucceeded = true;
        } catch (bytes memory reason) {
            reentryRevertData = reason;
        }
    }
}
