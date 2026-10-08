// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PersonalVault} from "../src/PersonalVault.sol";

/// @title PersonalVaultChecklistTest
/// @author Faiz A
/// @notice Reproduces the project brief's "Testing Checklist" step by step as one end-to-end scenario.
contract PersonalVaultChecklistTest is Test {
    uint256 internal constant START_TIME = 1_760_000_000;

    address internal owner = makeAddr("owner");

    function test_BriefTestingChecklist_EndToEnd() public {
        vm.warp(START_TIME);
        vm.deal(owner, 10 ether);
        vm.startPrank(owner);

        // 1. Deploy contract with unlockTime = 5 minutes from now.
        PersonalVault vault = new PersonalVault(START_TIME + 5 minutes);
        assertEq(vault.unlockTime(), START_TIME + 5 minutes);
        assertEq(vault.owner(), owner);

        // 2. Deposit 1 ETH -> should succeed, emit Deposit event.
        vm.expectEmit(true, false, false, true, address(vault));
        emit PersonalVault.Deposit(owner, 1 ether);
        vault.deposit{value: 1 ether}();
        assertEq(address(vault).balance, 1 ether);

        // 3. Try withdraw immediately -> should revert with FundsLocked().
        vm.expectRevert(PersonalVault.FundsLocked.selector);
        vault.withdraw();

        // 4. Extend lock to 10 minutes -> should succeed.
        vm.expectEmit(false, false, false, true, address(vault));
        emit PersonalVault.LockExtended(START_TIME + 10 minutes);
        vault.extendLock(START_TIME + 10 minutes);
        assertEq(vault.unlockTime(), START_TIME + 10 minutes);

        // 5. Try extend lock to 3 minutes -> should fail (cannot reduce).
        vm.expectRevert(PersonalVault.InvalidUnlockTime.selector);
        vault.extendLock(START_TIME + 3 minutes);
        assertEq(vault.unlockTime(), START_TIME + 10 minutes);

        // 6. Fast forward time to after unlock.
        vm.warp(START_TIME + 10 minutes + 1);
        assertTrue(vault.isUnlocked());

        // 7. Withdraw as owner -> should succeed, receive all ETH.
        uint256 ownerBalanceBefore = owner.balance;
        vm.expectEmit(false, false, false, true, address(vault));
        emit PersonalVault.Withdrawal(1 ether, block.timestamp);
        vault.withdraw();
        assertEq(owner.balance, ownerBalanceBefore + 1 ether);
        assertEq(address(vault).balance, 0);

        // 8. Try withdraw again -> should fail (no balance).
        vm.expectRevert(PersonalVault.NoBalance.selector);
        vault.withdraw();

        vm.stopPrank();
    }
}
