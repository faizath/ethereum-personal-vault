// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PersonalVault} from "../../src/PersonalVault.sol";

/// @title RejectingOwner
/// @author Faiz A
/// @notice Test double: a contract that owns a vault but cannot receive ETH (no `receive`/`fallback`).
/// @dev Used to prove that a failed payout reverts with {PersonalVault.TransferFailed} and keeps funds intact.
contract RejectingOwner {
    /// @notice The vault deployed (and therefore owned) by this contract.
    PersonalVault public immutable vault;

    /// @param unlockTime Unlock time forwarded to the vault constructor.
    constructor(uint256 unlockTime) {
        vault = new PersonalVault(unlockTime);
    }

    /// @notice Calls {PersonalVault.withdraw} as the owner.
    function withdraw() external {
        vault.withdraw();
    }
}
