// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PersonalVault} from "../../src/PersonalVault.sol";

/// @title VaultTestBase
/// @author Faiz A
/// @notice Shared fixture for PersonalVault tests: a vault owned by `owner`, locked for 5 minutes from a
///         realistic start timestamp, plus funded actors and small helpers.
abstract contract VaultTestBase is Test {
    /// @dev A realistic mainnet-era timestamp, so "past" timestamps are meaningful (Foundry starts at 1).
    uint256 internal constant START_TIME = 1_760_000_000;
    uint256 internal constant LOCK_DURATION = 5 minutes;
    uint256 internal constant DEPOSIT_AMOUNT = 1 ether;
    uint256 internal constant STARTING_BALANCE = 100 ether;

    PersonalVault internal vault;
    uint256 internal unlockTime;

    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public virtual {
        vm.warp(START_TIME);
        unlockTime = START_TIME + LOCK_DURATION;

        vm.prank(owner);
        vault = new PersonalVault(unlockTime);

        vm.deal(owner, STARTING_BALANCE);
        vm.deal(alice, STARTING_BALANCE);
        vm.deal(bob, STARTING_BALANCE);
    }

    /// @dev Deposits `amount` into the vault from `from` via {PersonalVault.deposit}.
    function _depositAs(address from, uint256 amount) internal {
        vm.prank(from);
        vault.deposit{value: amount}();
    }

    /// @dev Moves the chain to exactly the vault's current unlock time.
    function _warpToUnlock() internal {
        vm.warp(vault.unlockTime());
    }
}
