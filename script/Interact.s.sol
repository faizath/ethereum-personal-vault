// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PersonalVault} from "../src/PersonalVault.sol";

/// @title Interact
/// @author Faiz A
/// @notice Helpers for using a deployed {PersonalVault}, driven by environment variables.
/// @dev Requires `VAULT_ADDRESS`. Select an action with `--sig`, e.g.
///      forge script script/Interact.s.sol --sig "deposit()" --rpc-url sepolia --account deployer --broadcast
///      Note: forge simulates before broadcasting, so a call that reverts (e.g. an early withdrawal) is never
///      sent. To put a failing transaction on-chain on purpose, use `cast send --gas-limit` (see README).
contract Interact is Script {
    /// @notice Deposit amount used when `DEPOSIT_AMOUNT` is not set.
    uint256 public constant DEFAULT_DEPOSIT = 0.001 ether;

    /// @notice Extension used by {extendLock} when neither `NEW_UNLOCK_TIME` nor `EXTEND_BY` is set.
    uint256 public constant DEFAULT_EXTENSION = 5 minutes;

    /// @notice Default action: print the vault status (read-only, nothing is broadcast).
    function run() external view {
        _logStatus(_vault());
    }

    /// @notice Prints the vault status (read-only).
    function status() external view {
        _logStatus(_vault());
    }

    /// @notice Deposits `DEPOSIT_AMOUNT` wei (default 0.001 ETH) into the vault.
    function deposit() external {
        PersonalVault vault = _vault();
        uint256 amount = vm.envOr("DEPOSIT_AMOUNT", DEFAULT_DEPOSIT);

        vm.startBroadcast();
        vault.deposit{value: amount}();
        vm.stopBroadcast();

        console.log("Deposited (wei):", amount);
        _logStatus(vault);
    }

    /// @notice Withdraws the whole balance to the owner (the broadcaster must be the owner).
    function withdraw() external {
        PersonalVault vault = _vault();

        vm.startBroadcast();
        vault.withdraw();
        vm.stopBroadcast();

        _logStatus(vault);
    }

    /// @notice Extends the lock to `NEW_UNLOCK_TIME`, or by `EXTEND_BY` seconds (default 5 minutes) past
    ///         whichever is later: the current unlock time or now.
    function extendLock() external {
        PersonalVault vault = _vault();
        uint256 newTime = vm.envOr("NEW_UNLOCK_TIME", uint256(0));
        if (newTime == 0) {
            uint256 base = vault.unlockTime() > block.timestamp ? vault.unlockTime() : block.timestamp;
            newTime = base + vm.envOr("EXTEND_BY", DEFAULT_EXTENSION);
        }

        vm.startBroadcast();
        vault.extendLock(newTime);
        vm.stopBroadcast();

        _logStatus(vault);
    }

    function _vault() internal view returns (PersonalVault) {
        return PersonalVault(payable(vm.envAddress("VAULT_ADDRESS")));
    }

    function _logStatus(PersonalVault vault) internal view {
        console.log("Vault:                ", address(vault));
        console.log("Owner:                ", vault.owner());
        console.log("Balance (wei):        ", vault.balance());
        console.log("Unlock time (unix):   ", vault.unlockTime());
        console.log("Unlocked:             ", vault.isUnlocked());
        console.log("Seconds until unlock: ", vault.timeUntilUnlock());
    }
}
