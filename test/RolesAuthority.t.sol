// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Roles} from "../src/roles/Roles.sol";
import {Test, console} from "forge-std/Test.sol";
import {Authority} from "superlib/auth/Auth.sol";
import {RolesAuthority} from "superlib/auth/RolesAuthority.sol";
import {ERC20} from "superlib/core/ERC20.sol";

import {CrossChainRouter} from "../src/CrossChainRouter.sol";
import {ExecutionTrigger} from "../src/ExecutionTrigger.sol";
import {FeeVault} from "../src/FeeVault.sol";
import {FlashLoanEngine} from "../src/FlashLoanEngine.sol";
import {MEVProtector} from "../src/MEVProtector.sol";
import {RiskEngine} from "../src/RiskEngine.sol";

contract MockToken is ERC20 {

    constructor() ERC20("Mock", "MCK", 18) {
        _mint(msg.sender, 1_000_000e18);
    }

    function mint(
        address to,
        uint256 amount
    ) external {
        _mint(to, amount);
    }

}

contract RolesAuthorityTest is Test {

    RolesAuthority authority;
    MockToken token;
    FeeVault feeVault;
    MEVProtector mevProtector;
    FlashLoanEngine flashLoanEngine;
    CrossChainRouter crossChainRouter;
    RiskEngine riskEngine;
    ExecutionTrigger executionTrigger;

    address owner = makeAddr("owner");
    address executor = makeAddr("executor");
    address arbitrageManager = makeAddr("arbitrageManager");
    address riskManager = makeAddr("riskManager");
    address updater = makeAddr("updater");
    address guardian = makeAddr("guardian");
    address vaultDepositor = makeAddr("vaultDepositor");
    address whitelistAdmin = makeAddr("whitelistAdmin");
    address feeUpdater = makeAddr("feeUpdater");
    address attacker = makeAddr("attacker");

    function setUp() public {
        vm.startPrank(owner);

        authority = new RolesAuthority(owner, Authority(address(0)));
        token = new MockToken();

        feeVault = new FeeVault(token, "Vault", "VLT", owner, owner, authority);

        // Initialize dead shares for inflation attack protection
        token.approve(address(feeVault), 1000);
        feeVault.initializeDeadShares();

        mevProtector = new MEVProtector(owner, authority);
        flashLoanEngine = new FlashLoanEngine(owner, authority);
        crossChainRouter = new CrossChainRouter(owner, authority);
        riskEngine = new RiskEngine(owner, authority);
        executionTrigger = new ExecutionTrigger(owner, authority);

        _wireRoles();
        _assignRoles();

        token.mint(vaultDepositor, 100_000e18);
        vm.stopPrank();
    }

    function _wireRoles() internal {
        // FeeVault
        authority.setRoleCapability(Roles.VAULT_DEPOSITOR, address(feeVault), FeeVault.deposit.selector, true);
        authority.setRoleCapability(Roles.ADMIN, address(feeVault), FeeVault.withdraw.selector, true);
        authority.setRoleCapability(Roles.ADMIN, address(feeVault), FeeVault.redeem.selector, true);
        authority.setRoleCapability(Roles.FEE_UPDATER, address(feeVault), FeeVault.setDepositFee.selector, true);
        authority.setRoleCapability(Roles.ADMIN, address(feeVault), FeeVault.pause.selector, true);
        authority.setRoleCapability(Roles.GUARDIAN, address(feeVault), FeeVault.pause.selector, true);

        // MEVProtector
        authority.setRoleCapability(Roles.EXECUTOR, address(mevProtector), MEVProtector.commitExecution.selector, true);
        authority.setRoleCapability(
            Roles.EXECUTOR, address(mevProtector), MEVProtector.executeProtectedArbitrage.selector, true
        );
        authority.setRoleCapability(
            Roles.WHITELIST_ADMIN, address(mevProtector), MEVProtector.setTargetWhitelist.selector, true
        );

        // FlashLoanEngine
        authority.setRoleCapability(
            Roles.ARBITRAGE_MANAGER, address(flashLoanEngine), FlashLoanEngine.executeFlashLoanArbitrage.selector, true
        );
        authority.setRoleCapability(Roles.ADMIN, address(flashLoanEngine), FlashLoanEngine.addProvider.selector, true);

        // CrossChainRouter
        authority.setRoleCapability(
            Roles.ADMIN, address(crossChainRouter), CrossChainRouter.queueChainConfig.selector, true
        );
        authority.setRoleCapability(
            Roles.ADMIN, address(crossChainRouter), CrossChainRouter.executeChainConfig.selector, true
        );

        // RiskEngine
        authority.setRoleCapability(
            Roles.RISK_MANAGER, address(riskEngine), RiskEngine.setTokenRiskScore.selector, true
        );

        // ExecutionTrigger
        authority.setRoleCapability(
            Roles.EXECUTOR, address(executionTrigger), ExecutionTrigger.checkAndExecuteTriggers.selector, true
        );
        authority.setRoleCapability(
            Roles.UPDATER, address(executionTrigger), ExecutionTrigger.addTrigger.selector, true
        );
    }

    function _assignRoles() internal {
        authority.setUserRole(executor, Roles.EXECUTOR, true);
        authority.setUserRole(arbitrageManager, Roles.ARBITRAGE_MANAGER, true);
        authority.setUserRole(riskManager, Roles.RISK_MANAGER, true);
        authority.setUserRole(updater, Roles.UPDATER, true);
        authority.setUserRole(guardian, Roles.GUARDIAN, true);
        authority.setUserRole(vaultDepositor, Roles.VAULT_DEPOSITOR, true);
        authority.setUserRole(whitelistAdmin, Roles.WHITELIST_ADMIN, true);
        authority.setUserRole(feeUpdater, Roles.FEE_UPDATER, true);
    }

    /*//////////////////////////////////////////////////////////////
                        P0 FIX TESTS: VAULT SEPARATION
    //////////////////////////////////////////////////////////////*/

    function test_P0_VaultDepositorCanDeposit() public {
        vm.startPrank(vaultDepositor);
        token.approve(address(feeVault), 1000e18);
        feeVault.deposit(1000e18, vaultDepositor);
        vm.stopPrank();

        assertGt(feeVault.balanceOf(vaultDepositor), 0, "Depositor should have shares");
    }

    function test_P0_VaultDepositorCannotWithdraw() public {
        vm.startPrank(vaultDepositor);
        token.approve(address(feeVault), 1000e18);
        feeVault.deposit(1000e18, vaultDepositor);

        vm.expectRevert();
        feeVault.withdraw(500e18, vaultDepositor, vaultDepositor);
        vm.stopPrank();
    }

    function test_P0_OnlyAdminCanWithdraw() public {
        vm.startPrank(vaultDepositor);
        token.approve(address(feeVault), 1000e18);
        feeVault.deposit(1000e18, vaultDepositor);
        feeVault.approve(owner, type(uint256).max);
        vm.stopPrank();

        vm.prank(owner);
        feeVault.withdraw(100e18, owner, vaultDepositor);
        assertGt(token.balanceOf(owner), 0, "Admin should receive tokens");
    }

    /*//////////////////////////////////////////////////////////////
                        P0 FIX TESTS: MISSING BINDINGS
    //////////////////////////////////////////////////////////////*/

    function test_P0_ExecutorCanCommitExecution() public {
        vm.prank(executor);
        bytes32 hash = keccak256("test");
        mevProtector.commitExecution(hash);

        (bytes32 storedHash,) = mevProtector.getCommitment(executor);
        assertEq(storedHash, hash, "Commitment should be stored");
    }

    function test_P0_WhitelistAdminCanSetTargets() public {
        vm.prank(whitelistAdmin);
        mevProtector.setTargetWhitelist(address(token), true);

        assertTrue(mevProtector.whitelistedTargets(address(token)), "Target should be whitelisted");
    }

    function test_P0_UpdaterCanAddTrigger() public {
        vm.prank(updater);
        executionTrigger.addTrigger(keccak256("trigger1"), ExecutionTrigger.TriggerType.PriceThreshold, 1000, 60);

        assertEq(executionTrigger.getTriggerCount(), 1, "Trigger should be added");
    }

    function test_P0_AdminCanQueueChainConfig() public {
        vm.prank(owner);
        crossChainRouter.queueChainConfig(1, address(0x1), 100, 10_000, true);

        CrossChainRouter.PendingConfig memory pending = crossChainRouter.getPendingConfig(1);
        assertTrue(pending.exists, "Pending config should exist");
        assertGt(pending.executeAfter, block.timestamp, "Should have timelock");
    }

    /*//////////////////////////////////////////////////////////////
                        P1 FIX TESTS: ROLE SEPARATION
    //////////////////////////////////////////////////////////////*/

    function test_P1_GuardianCanPause() public {
        vm.prank(guardian);
        feeVault.pause();

        assertTrue(feeVault.paused(), "Vault should be paused");
    }

    function test_P1_FeeUpdaterCanSetFees() public {
        vm.prank(feeUpdater);
        feeVault.setDepositFee(100);

        assertEq(feeVault.depositFee(), 100, "Fee should be updated");
    }

    function test_P1_FeeUpdaterCannotPause() public {
        vm.prank(feeUpdater);
        vm.expectRevert();
        feeVault.pause();
    }

    /*//////////////////////////////////////////////////////////////
                        SECURITY INVARIANT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_AttackerCannotAccessProtectedFunctions() public {
        vm.startPrank(attacker);

        vm.expectRevert();
        feeVault.pause();

        vm.expectRevert();
        feeVault.setDepositFee(1000);

        vm.expectRevert();
        mevProtector.setTargetWhitelist(address(token), true);

        vm.expectRevert();
        flashLoanEngine.addProvider(keccak256("test"), address(0x1), 10);

        vm.expectRevert();
        riskEngine.setTokenRiskScore(address(token), 50);

        vm.stopPrank();
    }

    function test_RolesCannotEscalate() public {
        vm.startPrank(executor);

        vm.expectRevert();
        authority.setUserRole(attacker, Roles.ADMIN, true);

        vm.expectRevert();
        authority.setRoleCapability(Roles.EXECUTOR, address(feeVault), FeeVault.emergencyWithdraw.selector, true);

        vm.stopPrank();
    }

    function test_OnlyOwnerCanGrantRoles() public {
        vm.prank(owner);
        authority.setUserRole(attacker, Roles.EXECUTOR, true);

        assertTrue(authority.doesUserHaveRole(attacker, Roles.EXECUTOR), "Owner should grant roles");
    }

    /*//////////////////////////////////////////////////////////////
                        ROLE MATRIX VALIDATION
    //////////////////////////////////////////////////////////////*/

    function test_RoleMatrixExecutor() public view {
        assertTrue(authority.canCall(executor, address(mevProtector), MEVProtector.commitExecution.selector));
        assertTrue(authority.canCall(executor, address(mevProtector), MEVProtector.executeProtectedArbitrage.selector));
        assertTrue(
            authority.canCall(executor, address(executionTrigger), ExecutionTrigger.checkAndExecuteTriggers.selector)
        );

        assertFalse(authority.canCall(executor, address(feeVault), FeeVault.withdraw.selector));
        assertFalse(authority.canCall(executor, address(riskEngine), RiskEngine.setTokenRiskScore.selector));
    }

    function test_RoleMatrixArbitrageManager() public view {
        assertTrue(
            authority.canCall(
                arbitrageManager, address(flashLoanEngine), FlashLoanEngine.executeFlashLoanArbitrage.selector
            )
        );

        assertFalse(authority.canCall(arbitrageManager, address(feeVault), FeeVault.withdraw.selector));
        assertFalse(authority.canCall(arbitrageManager, address(feeVault), FeeVault.pause.selector));
    }

    function test_RoleMatrixRiskManager() public view {
        assertTrue(authority.canCall(riskManager, address(riskEngine), RiskEngine.setTokenRiskScore.selector));

        assertFalse(authority.canCall(riskManager, address(feeVault), FeeVault.withdraw.selector));
        assertFalse(authority.canCall(riskManager, address(flashLoanEngine), FlashLoanEngine.addProvider.selector));
    }

}
