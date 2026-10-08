// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PersonalVault} from "../src/PersonalVault.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {Interact} from "../script/Interact.s.sol";

/// @title ScriptsTest
/// @author Faiz A
/// @notice Exercises the deployment and interaction scripts against a local chain.
/// @dev Environment variables are process-wide and tests run in parallel, so every env-dependent flow lives in
///      exactly one test function and sets all variables it reads.
contract ScriptsTest is Test {
    uint256 internal constant START_TIME = 1_760_000_000;

    Deploy internal deployer;
    Interact internal interact;

    function setUp() public {
        vm.warp(START_TIME);
        deployer = new Deploy();
        interact = new Interact();
        vm.deal(DEFAULT_SENDER, 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                                 DEPLOY
    //////////////////////////////////////////////////////////////*/

    function test_ResolveUnlockTime_UsesDurationWhenNoAbsoluteTime() public view {
        assertEq(deployer.resolveUnlockTime(0, 1 hours), START_TIME + 1 hours);
    }

    function test_ResolveUnlockTime_PrefersAbsoluteTime() public view {
        assertEq(deployer.resolveUnlockTime(START_TIME + 1 days, 1 hours), START_TIME + 1 days);
    }

    function test_ResolveUnlockTime_RevertsWhen_NotInFuture() public {
        vm.expectRevert(abi.encodeWithSelector(Deploy.UnlockTimeNotInFuture.selector, START_TIME - 1, START_TIME));
        deployer.resolveUnlockTime(START_TIME - 1, 0);

        vm.expectRevert(abi.encodeWithSelector(Deploy.UnlockTimeNotInFuture.selector, START_TIME, START_TIME));
        deployer.resolveUnlockTime(0, 0);
    }

    function test_ResolveUnlockTime_RevertsWhen_MillisecondTimestamp() public {
        uint256 millis = (START_TIME + 1 hours) * 1000;
        uint256 maxUnlockTime = START_TIME + deployer.MAX_LOCK_DURATION();

        vm.expectRevert(abi.encodeWithSelector(Deploy.UnlockTimeTooFar.selector, millis, maxUnlockTime));
        deployer.resolveUnlockTime(millis, 0);
    }

    function test_Deploy_BroadcasterIsOwnerAndInitialDepositIsLocked() public {
        PersonalVault vault = deployer.deploy(START_TIME + 1 hours, 1 ether);

        assertEq(vault.owner(), DEFAULT_SENDER);
        assertEq(vault.unlockTime(), START_TIME + 1 hours);
        assertEq(address(vault).balance, 1 ether);
    }

    function test_Run_ReadsConfigurationFromEnvironment() public {
        vm.setEnv("UNLOCK_TIME", "0");
        vm.setEnv("LOCK_DURATION", "900");
        vm.setEnv("INITIAL_DEPOSIT", "1000000000000000");

        PersonalVault vault = deployer.run();

        assertEq(vault.unlockTime(), START_TIME + 900);
        assertEq(address(vault).balance, 0.001 ether);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERACT
    //////////////////////////////////////////////////////////////*/

    function test_Interact_DepositExtendWithdrawFlow() public {
        vm.prank(DEFAULT_SENDER);
        PersonalVault vault = new PersonalVault(START_TIME + 5 minutes);

        vm.setEnv("VAULT_ADDRESS", vm.toString(address(vault)));
        vm.setEnv("DEPOSIT_AMOUNT", "20000000000000000");
        vm.setEnv("NEW_UNLOCK_TIME", "0");
        vm.setEnv("EXTEND_BY", "600");

        interact.run();

        interact.deposit();
        assertEq(address(vault).balance, 0.02 ether);

        vm.expectRevert(PersonalVault.FundsLocked.selector);
        vm.prank(DEFAULT_SENDER);
        vault.withdraw();

        interact.extendLock();
        assertEq(vault.unlockTime(), START_TIME + 5 minutes + 600);

        vm.setEnv("NEW_UNLOCK_TIME", vm.toString(START_TIME + 1 hours));
        interact.extendLock();
        assertEq(vault.unlockTime(), START_TIME + 1 hours);

        vm.warp(vault.unlockTime());
        uint256 ownerBalanceBefore = DEFAULT_SENDER.balance;
        interact.withdraw();

        assertEq(address(vault).balance, 0);
        assertEq(DEFAULT_SENDER.balance, ownerBalanceBefore + 0.02 ether);

        vm.setEnv("NEW_UNLOCK_TIME", "0");
        interact.extendLock();
        assertEq(vault.unlockTime(), block.timestamp + 600, "re-lock counts from now once unlocked");
        interact.status();
    }
}
