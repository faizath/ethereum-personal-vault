// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PersonalVault} from "../src/PersonalVault.sol";

/// @title Deploy
/// @author Faiz A
/// @notice Deploys {PersonalVault}. The broadcaster becomes the vault owner.
/// @dev Environment variables (all optional):
///      - `UNLOCK_TIME`     absolute unix timestamp in seconds; takes precedence over `LOCK_DURATION`.
///      - `LOCK_DURATION`   seconds from the current block to unlock (default: 10 minutes).
///      - `INITIAL_DEPOSIT` wei to send with the deployment (default: 0).
///      The signer is never read from the environment here; pass it on the command line with
///      `--account <keystore>` (recommended) or `--private-key`.
///
///      forge script script/Deploy.s.sol --rpc-url sepolia --account deployer --broadcast --verify
contract Deploy is Script {
    /// @notice Lock duration used when neither `UNLOCK_TIME` nor `LOCK_DURATION` is set.
    uint256 public constant DEFAULT_LOCK_DURATION = 10 minutes;

    /// @notice Sanity cap for scripted deployments, e.g. catching a millisecond timestamp passed by mistake.
    /// @dev Script-side guard only; the contract itself accepts any future unlock time.
    uint256 public constant MAX_LOCK_DURATION = 10 * 365 days;

    /// @notice Thrown when the resolved unlock time is not after the current block timestamp.
    error UnlockTimeNotInFuture(uint256 unlockTime, uint256 currentTime);

    /// @notice Thrown when the resolved unlock time is more than `MAX_LOCK_DURATION` away.
    error UnlockTimeTooFar(uint256 unlockTime, uint256 maxUnlockTime);

    /// @notice Entry point: resolves configuration from the environment and deploys the vault.
    /// @return vault The deployed vault.
    function run() external returns (PersonalVault vault) {
        uint256 unlockTime =
            resolveUnlockTime(vm.envOr("UNLOCK_TIME", uint256(0)), vm.envOr("LOCK_DURATION", DEFAULT_LOCK_DURATION));
        vault = deploy(unlockTime, vm.envOr("INITIAL_DEPOSIT", uint256(0)));
    }

    /// @notice Broadcasts the vault deployment and logs the result.
    /// @param unlockTime Unix timestamp (seconds) from which funds can be withdrawn.
    /// @param initialDeposit Wei to lock at deployment.
    /// @return vault The deployed vault.
    function deploy(uint256 unlockTime, uint256 initialDeposit) public returns (PersonalVault vault) {
        vm.startBroadcast();
        vault = new PersonalVault{value: initialDeposit}(unlockTime);
        vm.stopBroadcast();

        console.log("PersonalVault deployed at:", address(vault));
        console.log("Owner:                    ", vault.owner());
        console.log("Unlock time (unix):       ", vault.unlockTime());
        console.log("Initial deposit (wei):    ", initialDeposit);
    }

    /// @notice Picks the unlock time from an absolute timestamp or a duration and sanity-checks it.
    /// @param absoluteUnlockTime Absolute unix timestamp, or 0 to use `lockDuration` instead.
    /// @param lockDuration Seconds from the current block, used when `absoluteUnlockTime` is 0.
    /// @return unlockTime The validated unlock timestamp.
    function resolveUnlockTime(uint256 absoluteUnlockTime, uint256 lockDuration)
        public
        view
        returns (uint256 unlockTime)
    {
        unlockTime = absoluteUnlockTime != 0 ? absoluteUnlockTime : block.timestamp + lockDuration;
        if (unlockTime <= block.timestamp) revert UnlockTimeNotInFuture(unlockTime, block.timestamp);
        uint256 maxUnlockTime = block.timestamp + MAX_LOCK_DURATION;
        if (unlockTime > maxUnlockTime) revert UnlockTimeTooFar(unlockTime, maxUnlockTime);
    }
}
