// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {RolesAuthority} from "superlib/auth/RolesAuthority.sol";
import {Authority} from "superlib/auth/Auth.sol";
import {ERC20} from "superlib/core/ERC20.sol";
import {Roles} from "../src/roles/Roles.sol";

import {FeeVault} from "../src/FeeVault.sol";
import {MEVProtector} from "../src/MEVProtector.sol";
import {FlashLoanEngine} from "../src/FlashLoanEngine.sol";
import {CrossChainRouter} from "../src/CrossChainRouter.sol";
import {RiskEngine} from "../src/RiskEngine.sol";
import {ExecutionTrigger} from "../src/ExecutionTrigger.sol";
import {MaximumSecurityEngine} from "../src/MaximumSecurityEngine.sol";
import {StrategyOrchestrator} from "../src/StrategyOrchestrator.sol";
import {MinimumCostExecutor} from "../src/MinimumCostExecutor.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MCK", 18) {
        _mint(msg.sender, 1_000_000e18);
    }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

/// @title RolesAuthorityHandler
/// @notice Fuzzing handler that simulates random role/capability operations
contract RolesAuthorityHandler is Test {
    RolesAuthority public authority;
    address public owner;
    address[] public actors;
    address[] public targets;
    bytes4[] public selectors;
    
    uint256 public callCount;
    uint256 public escalationAttempts;
    uint256 public successfulEscalations;

    constructor(
        RolesAuthority _authority,
        address _owner,
        address[] memory _actors,
        address[] memory _targets,
        bytes4[] memory _selectors
    ) {
        authority = _authority;
        owner = _owner;
        actors = _actors;
        targets = _targets;
        selectors = _selectors;
    }

    /// @notice Attempt to grant a role from a non-owner actor
    function attemptGrantRole(uint256 actorSeed, uint256 targetSeed, uint8 role) external {
        callCount++;
        address actor = actors[actorSeed % actors.length];
        address target = actors[targetSeed % actors.length];
        
        if (actor == owner) return; // Skip owner - they're allowed
        
        escalationAttempts++;
        
        vm.prank(actor);
        try authority.setUserRole(target, role % 11, true) {
            successfulEscalations++;
        } catch {}
    }

    /// @notice Attempt to set capability from a non-owner actor
    function attemptSetCapability(
        uint256 actorSeed,
        uint256 targetSeed,
        uint256 selectorSeed,
        uint8 role
    ) external {
        callCount++;
        address actor = actors[actorSeed % actors.length];
        address target = targets[targetSeed % targets.length];
        bytes4 selector = selectors[selectorSeed % selectors.length];
        
        if (actor == owner) return;
        
        escalationAttempts++;
        
        vm.prank(actor);
        try authority.setRoleCapability(role % 11, target, selector, true) {
            successfulEscalations++;
        } catch {}
    }

    /// @notice Attempt to set public capability from non-owner
    function attemptSetPublicCapability(
        uint256 actorSeed,
        uint256 targetSeed,
        uint256 selectorSeed
    ) external {
        callCount++;
        address actor = actors[actorSeed % actors.length];
        address target = targets[targetSeed % targets.length];
        bytes4 selector = selectors[selectorSeed % selectors.length];
        
        if (actor == owner) return;
        
        escalationAttempts++;
        
        vm.prank(actor);
        try authority.setPublicCapability(target, selector, true) {
            successfulEscalations++;
        } catch {}
    }
}

/// @title ProtocolHandler
/// @notice Fuzzing handler that simulates protocol operations with various roles
contract ProtocolHandler is Test {
    RolesAuthority public authority;
    FeeVault public feeVault;
    MEVProtector public mevProtector;
    FlashLoanEngine public flashLoanEngine;
    RiskEngine public riskEngine;
    MockToken public token;
    
    address public owner;
    address public executor;
    address public arbitrageManager;
    address public vaultDepositor;
    address public attacker;
    
    uint256 public unauthorizedWithdrawAttempts;
    uint256 public successfulUnauthorizedWithdraws;
    uint256 public unauthorizedPauseAttempts;
    uint256 public successfulUnauthorizedPauses;
    uint256 public unauthorizedWhitelistAttempts;
    uint256 public successfulUnauthorizedWhitelists;

    constructor(
        RolesAuthority _authority,
        FeeVault _feeVault,
        MEVProtector _mevProtector,
        FlashLoanEngine _flashLoanEngine,
        RiskEngine _riskEngine,
        MockToken _token,
        address _owner,
        address _executor,
        address _arbitrageManager,
        address _vaultDepositor,
        address _attacker
    ) {
        authority = _authority;
        feeVault = _feeVault;
        mevProtector = _mevProtector;
        flashLoanEngine = _flashLoanEngine;
        riskEngine = _riskEngine;
        token = _token;
        owner = _owner;
        executor = _executor;
        arbitrageManager = _arbitrageManager;
        vaultDepositor = _vaultDepositor;
        attacker = _attacker;
    }

    /// @notice Vault depositor deposits (should succeed)
    function depositorDeposit(uint256 amount) external {
        amount = bound(amount, 1e18, 10_000e18);
        
        vm.startPrank(vaultDepositor);
        token.approve(address(feeVault), amount);
        try feeVault.deposit(amount, vaultDepositor) {} catch {}
        vm.stopPrank();
    }

    /// @notice Vault depositor attempts withdrawal (should fail - P0 invariant)
    function depositorAttemptWithdraw(uint256 amount) external {
        amount = bound(amount, 1e18, 10_000e18);
        uint256 shares = feeVault.balanceOf(vaultDepositor);
        if (shares == 0) return;
        
        unauthorizedWithdrawAttempts++;
        
        vm.prank(vaultDepositor);
        try feeVault.withdraw(amount, vaultDepositor, vaultDepositor) {
            successfulUnauthorizedWithdraws++;
        } catch {}
    }

    /// @notice Attacker attempts withdrawal (should fail)
    function attackerAttemptWithdraw(uint256 amount) external {
        amount = bound(amount, 1e18, 10_000e18);
        
        unauthorizedWithdrawAttempts++;
        
        vm.prank(attacker);
        try feeVault.withdraw(amount, attacker, attacker) {
            successfulUnauthorizedWithdraws++;
        } catch {}
    }

    /// @notice Attacker attempts to pause vault (should fail)
    function attackerAttemptPause() external {
        unauthorizedPauseAttempts++;
        
        vm.prank(attacker);
        try feeVault.pause() {
            successfulUnauthorizedPauses++;
        } catch {}
    }

    /// @notice Executor attempts to pause vault (should fail - wrong role)
    function executorAttemptPause() external {
        unauthorizedPauseAttempts++;
        
        vm.prank(executor);
        try feeVault.pause() {
            successfulUnauthorizedPauses++;
        } catch {}
    }

    /// @notice Attacker attempts whitelist modification (should fail)
    function attackerAttemptWhitelist(address target) external {
        unauthorizedWhitelistAttempts++;
        
        vm.prank(attacker);
        try mevProtector.setTargetWhitelist(target, true) {
            successfulUnauthorizedWhitelists++;
        } catch {}
    }

    /// @notice Executor attempts whitelist (should fail - wrong role)
    function executorAttemptWhitelist(address target) external {
        unauthorizedWhitelistAttempts++;
        
        vm.prank(executor);
        try mevProtector.setTargetWhitelist(target, true) {
            successfulUnauthorizedWhitelists++;
        } catch {}
    }
}

/// @title RolesInvariantTest
/// @notice Invariant/fuzz tests proving no privilege escalation paths exist
contract RolesInvariantTest is StdInvariant, Test {
    RolesAuthority authority;
    MockToken token;
    FeeVault feeVault;
    MEVProtector mevProtector;
    FlashLoanEngine flashLoanEngine;
    CrossChainRouter crossChainRouter;
    RiskEngine riskEngine;
    ExecutionTrigger executionTrigger;
    MaximumSecurityEngine maxSecurityEngine;
    StrategyOrchestrator strategyOrchestrator;
    MinimumCostExecutor minimumCostExecutor;

    RolesAuthorityHandler authorityHandler;
    ProtocolHandler protocolHandler;

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

        // Deploy core
        authority = new RolesAuthority(owner, Authority(address(0)));
        token = new MockToken();

        // Deploy contracts
        feeVault = new FeeVault(token, "Vault", "VLT", owner, owner, authority);
        token.approve(address(feeVault), 1000);
        feeVault.initializeDeadShares();
        
        mevProtector = new MEVProtector(owner, authority);
        flashLoanEngine = new FlashLoanEngine(owner, authority);
        crossChainRouter = new CrossChainRouter(owner, authority);
        riskEngine = new RiskEngine(owner, authority);
        executionTrigger = new ExecutionTrigger(owner, authority);
        maxSecurityEngine = new MaximumSecurityEngine(owner, authority);
        strategyOrchestrator = new StrategyOrchestrator(owner, authority);
        minimumCostExecutor = new MinimumCostExecutor(owner, authority);

        // Wire roles (same as production)
        _wireRoles();
        _assignRoles();

        // Fund actors
        token.mint(vaultDepositor, 1_000_000e18);
        token.mint(attacker, 1_000_000e18);

        vm.stopPrank();

        // Setup handlers
        address[] memory actors = new address[](10);
        actors[0] = executor;
        actors[1] = arbitrageManager;
        actors[2] = riskManager;
        actors[3] = updater;
        actors[4] = guardian;
        actors[5] = vaultDepositor;
        actors[6] = whitelistAdmin;
        actors[7] = feeUpdater;
        actors[8] = attacker;
        actors[9] = makeAddr("randomUser");

        address[] memory targets = new address[](9);
        targets[0] = address(feeVault);
        targets[1] = address(mevProtector);
        targets[2] = address(flashLoanEngine);
        targets[3] = address(crossChainRouter);
        targets[4] = address(riskEngine);
        targets[5] = address(executionTrigger);
        targets[6] = address(maxSecurityEngine);
        targets[7] = address(strategyOrchestrator);
        targets[8] = address(minimumCostExecutor);

        bytes4[] memory selectors = new bytes4[](12);
        selectors[0] = FeeVault.deposit.selector;
        selectors[1] = FeeVault.withdraw.selector;
        selectors[2] = FeeVault.pause.selector;
        selectors[3] = FeeVault.emergencyWithdraw.selector;
        selectors[4] = MEVProtector.setTargetWhitelist.selector;
        selectors[5] = MEVProtector.commitExecution.selector;
        selectors[6] = FlashLoanEngine.addProvider.selector;
        selectors[7] = RiskEngine.setTokenRiskScore.selector;
        selectors[8] = CrossChainRouter.queueChainConfig.selector;
        selectors[9] = ExecutionTrigger.addTrigger.selector;
        selectors[10] = MaximumSecurityEngine.setSecurityConfig.selector;
        selectors[11] = StrategyOrchestrator.addStrategy.selector;

        authorityHandler = new RolesAuthorityHandler(
            authority,
            owner,
            actors,
            targets,
            selectors
        );

        protocolHandler = new ProtocolHandler(
            authority,
            feeVault,
            mevProtector,
            flashLoanEngine,
            riskEngine,
            token,
            owner,
            executor,
            arbitrageManager,
            vaultDepositor,
            attacker
        );

        // Target handlers for invariant testing
        targetContract(address(authorityHandler));
        targetContract(address(protocolHandler));
    }

    function _wireRoles() internal {
        // FeeVault - P0 FIX
        authority.setRoleCapability(Roles.VAULT_DEPOSITOR, address(feeVault), FeeVault.deposit.selector, true);
        authority.setRoleCapability(Roles.ADMIN, address(feeVault), FeeVault.withdraw.selector, true);
        authority.setRoleCapability(Roles.ADMIN, address(feeVault), FeeVault.redeem.selector, true);
        authority.setRoleCapability(Roles.FEE_UPDATER, address(feeVault), FeeVault.setDepositFee.selector, true);
        authority.setRoleCapability(Roles.ADMIN, address(feeVault), FeeVault.pause.selector, true);
        authority.setRoleCapability(Roles.GUARDIAN, address(feeVault), FeeVault.pause.selector, true);
        authority.setRoleCapability(Roles.ADMIN, address(feeVault), FeeVault.emergencyWithdraw.selector, true);

        // MEVProtector - P0 FIX
        authority.setRoleCapability(Roles.EXECUTOR, address(mevProtector), MEVProtector.commitExecution.selector, true);
        authority.setRoleCapability(Roles.EXECUTOR, address(mevProtector), MEVProtector.executeProtectedArbitrage.selector, true);
        authority.setRoleCapability(Roles.WHITELIST_ADMIN, address(mevProtector), MEVProtector.setTargetWhitelist.selector, true);
        authority.setRoleCapability(Roles.WHITELIST_ADMIN, address(mevProtector), MEVProtector.setSelectorWhitelist.selector, true);

        // FlashLoanEngine
        authority.setRoleCapability(Roles.ARBITRAGE_MANAGER, address(flashLoanEngine), FlashLoanEngine.executeFlashLoanArbitrage.selector, true);
        authority.setRoleCapability(Roles.ADMIN, address(flashLoanEngine), FlashLoanEngine.addProvider.selector, true);

        // CrossChainRouter - P0 FIX
        authority.setRoleCapability(Roles.ADMIN, address(crossChainRouter), CrossChainRouter.queueChainConfig.selector, true);
        authority.setRoleCapability(Roles.ADMIN, address(crossChainRouter), CrossChainRouter.executeChainConfig.selector, true);

        // RiskEngine
        authority.setRoleCapability(Roles.RISK_MANAGER, address(riskEngine), RiskEngine.setTokenRiskScore.selector, true);

        // ExecutionTrigger
        authority.setRoleCapability(Roles.EXECUTOR, address(executionTrigger), ExecutionTrigger.checkAndExecuteTriggers.selector, true);
        authority.setRoleCapability(Roles.UPDATER, address(executionTrigger), ExecutionTrigger.addTrigger.selector, true);

        // MaxSecurityEngine
        authority.setRoleCapability(Roles.EXECUTOR, address(maxSecurityEngine), MaximumSecurityEngine.executeWithMaximumSecurity.selector, true);
        authority.setRoleCapability(Roles.RISK_MANAGER, address(maxSecurityEngine), MaximumSecurityEngine.setSecurityConfig.selector, true);

        // StrategyOrchestrator
        authority.setRoleCapability(Roles.STRATEGY_MANAGER, address(strategyOrchestrator), StrategyOrchestrator.addStrategy.selector, true);
        authority.setRoleCapability(Roles.ARBITRAGE_MANAGER, address(strategyOrchestrator), StrategyOrchestrator.executeStrategyFlow.selector, true);

        // MinimumCostExecutor
        authority.setRoleCapability(Roles.EXECUTOR, address(minimumCostExecutor), MinimumCostExecutor.executeWithMinimumCost.selector, true);
    }

    function _assignRoles() internal {
        // Owner gets ADMIN role
        authority.setUserRole(owner, Roles.ADMIN, true);
        
        authority.setUserRole(executor, Roles.EXECUTOR, true);
        authority.setUserRole(arbitrageManager, Roles.ARBITRAGE_MANAGER, true);
        authority.setUserRole(riskManager, Roles.RISK_MANAGER, true);
        authority.setUserRole(updater, Roles.UPDATER, true);
        authority.setUserRole(guardian, Roles.GUARDIAN, true);
        authority.setUserRole(vaultDepositor, Roles.VAULT_DEPOSITOR, true);
        authority.setUserRole(whitelistAdmin, Roles.WHITELIST_ADMIN, true);
        authority.setUserRole(feeUpdater, Roles.FEE_UPDATER, true);
        // attacker gets NO roles
    }

    /*//////////////////////////////////////////////////////////////
                            INVARIANT TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice INVARIANT: No non-owner can ever grant roles
    function invariant_noUnauthorizedRoleGrants() public view {
        assertEq(
            authorityHandler.successfulEscalations(),
            0,
            "CRITICAL: Unauthorized role grant detected"
        );
    }

    /// @notice INVARIANT: No unauthorized withdrawals from vault (P0)
    function invariant_noUnauthorizedWithdrawals() public view {
        assertEq(
            protocolHandler.successfulUnauthorizedWithdraws(),
            0,
            "CRITICAL: Unauthorized vault withdrawal detected"
        );
    }

    /// @notice INVARIANT: No unauthorized pauses (P1)
    function invariant_noUnauthorizedPauses() public view {
        assertEq(
            protocolHandler.successfulUnauthorizedPauses(),
            0,
            "CRITICAL: Unauthorized pause detected"
        );
    }

    /// @notice INVARIANT: No unauthorized whitelist modifications (P0)
    function invariant_noUnauthorizedWhitelistChanges() public view {
        assertEq(
            protocolHandler.successfulUnauthorizedWhitelists(),
            0,
            "CRITICAL: Unauthorized whitelist modification detected"
        );
    }

    /// @notice INVARIANT: Owner always retains admin role
    function invariant_ownerRetainsAdmin() public view {
        // Owner should always have ADMIN role
        assertTrue(
            authority.doesUserHaveRole(owner, Roles.ADMIN),
            "Owner lost ADMIN role"
        );
        // ADMIN role should always have withdraw capability
        assertTrue(
            authority.doesRoleHaveCapability(Roles.ADMIN, address(feeVault), FeeVault.withdraw.selector),
            "ADMIN lost withdraw capability"
        );
        // ADMIN role should always have pause capability
        assertTrue(
            authority.doesRoleHaveCapability(Roles.ADMIN, address(feeVault), FeeVault.pause.selector),
            "ADMIN lost pause capability"
        );
    }

    /// @notice INVARIANT: Attacker never gains any capabilities
    function invariant_attackerHasNoCapabilities() public view {
        assertFalse(authority.canCall(attacker, address(feeVault), FeeVault.deposit.selector));
        assertFalse(authority.canCall(attacker, address(feeVault), FeeVault.withdraw.selector));
        assertFalse(authority.canCall(attacker, address(feeVault), FeeVault.pause.selector));
        assertFalse(authority.canCall(attacker, address(mevProtector), MEVProtector.setTargetWhitelist.selector));
        assertFalse(authority.canCall(attacker, address(flashLoanEngine), FlashLoanEngine.addProvider.selector));
    }

    /// @notice INVARIANT: VAULT_DEPOSITOR cannot withdraw (P0 core invariant)
    function invariant_depositorCannotWithdraw() public view {
        assertFalse(
            authority.canCall(vaultDepositor, address(feeVault), FeeVault.withdraw.selector),
            "P0 VIOLATION: Depositor can withdraw"
        );
        assertFalse(
            authority.canCall(vaultDepositor, address(feeVault), FeeVault.redeem.selector),
            "P0 VIOLATION: Depositor can redeem"
        );
    }

    /// @notice INVARIANT: Role separation maintained - executor cannot manage whitelists
    function invariant_executorCannotManageWhitelists() public view {
        assertFalse(
            authority.canCall(executor, address(mevProtector), MEVProtector.setTargetWhitelist.selector),
            "Role separation violated: executor has whitelist access"
        );
    }

    /// @notice INVARIANT: Role separation maintained - fee updater cannot pause
    function invariant_feeUpdaterCannotPause() public view {
        assertFalse(
            authority.canCall(feeUpdater, address(feeVault), FeeVault.pause.selector),
            "Role separation violated: fee updater can pause"
        );
    }

    /*//////////////////////////////////////////////////////////////
                          CALL SUMMARY (for debugging)
    //////////////////////////////////////////////////////////////*/

    function invariant_callSummary() public view {
        console.log("=== Invariant Test Summary ===");
        console.log("Authority handler calls:", authorityHandler.callCount());
        console.log("Escalation attempts:", authorityHandler.escalationAttempts());
        console.log("Successful escalations:", authorityHandler.successfulEscalations());
        console.log("");
        console.log("Unauthorized withdraw attempts:", protocolHandler.unauthorizedWithdrawAttempts());
        console.log("Successful unauthorized withdraws:", protocolHandler.successfulUnauthorizedWithdraws());
        console.log("Unauthorized pause attempts:", protocolHandler.unauthorizedPauseAttempts());
        console.log("Successful unauthorized pauses:", protocolHandler.successfulUnauthorizedPauses());
        console.log("Unauthorized whitelist attempts:", protocolHandler.unauthorizedWhitelistAttempts());
        console.log("Successful unauthorized whitelists:", protocolHandler.successfulUnauthorizedWhitelists());
    }
}
