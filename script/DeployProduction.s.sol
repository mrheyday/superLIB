// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Script, console} from "forge-std/Script.sol";
import {RolesAuthority} from "superlib/auth/RolesAuthority.sol";
import {Authority} from "superlib/auth/Auth.sol";
import {ERC20} from "superlib/core/ERC20.sol";
import {Roles} from "../src/roles/Roles.sol";

import {FeeVault} from "../src/FeeVault.sol";
import {MEVProtector} from "../src/MEVProtector.sol";
import {FlashLoanEngine} from "../src/FlashLoanEngine.sol";
import {CrossChainRouter} from "../src/CrossChainRouter.sol";
import {MaximumSecurityEngine} from "../src/MaximumSecurityEngine.sol";
import {RiskEngine} from "../src/RiskEngine.sol";
import {StrategyOrchestrator} from "../src/StrategyOrchestrator.sol";
import {QuantumArbitrage} from "../src/QuantumArbitrage.sol";
import {UltimateArbitrageEngine} from "../src/UltimateArbitrageEngine.sol";
import {ExecutionTrigger} from "../src/ExecutionTrigger.sol";
import {MinimumCostExecutor} from "../src/MinimumCostExecutor.sol";
import {StrategyAnalytics} from "../src/StrategyAnalytics.sol";
import {ExecutionAnalytics} from "../src/ExecutionAnalytics.sol";
import {IntelligenceProcessor} from "../src/IntelligenceProcessor.sol";

/// @title DeployProduction
/// @notice Production-grade deployment with complete role wiring per audit spec v1.1
/// @dev Implements all P0/P1 fixes: vault separation, granular roles, guardian, whitelist elevation
contract DeployProduction is Script {
    // Deployed contracts
    RolesAuthority public authority;
    FeeVault public feeVault;
    MEVProtector public mevProtector;
    FlashLoanEngine public flashLoanEngine;
    CrossChainRouter public crossChainRouter;
    MaximumSecurityEngine public maxSecurityEngine;
    RiskEngine public riskEngine;
    StrategyOrchestrator public strategyOrchestrator;
    QuantumArbitrage public quantumArbitrage;
    UltimateArbitrageEngine public ultimateArbitrageEngine;
    ExecutionTrigger public executionTrigger;
    MinimumCostExecutor public minimumCostExecutor;
    StrategyAnalytics public strategyAnalytics;
    ExecutionAnalytics public executionAnalytics;
    IntelligenceProcessor public intelligenceProcessor;

    // Configuration
    struct DeployConfig {
        address ownerMultisig; // Gnosis Safe 3-of-5
        address guardian; // Fast-response EOA for emergencies
        address aiAgent; // Autonomous execution agent
        address assetToken; // Vault underlying (USDC/WETH)
        address feeRecipient; // Protocol fee destination
        uint256 chainId; // Target chain
    }

    function run() external {
        DeployConfig memory config = _loadConfig();

        console.log("=== Production Deployment ===");
        console.log("Chain ID:", config.chainId);
        console.log("Owner Multisig:", config.ownerMultisig);
        console.log("Guardian:", config.guardian);
        console.log("AI Agent:", config.aiAgent);
        console.log("Asset Token:", config.assetToken);
        console.log("");

        vm.startBroadcast();

        // Phase 1: Deploy Authority
        authority = new RolesAuthority(config.ownerMultisig, Authority(address(0)));
        console.log("RolesAuthority deployed:", address(authority));

        // Phase 2: Deploy Core Contracts
        _deployContracts(config);

        // Phase 3: Wire All Role Capabilities (67 bindings)
        _wireAllCapabilities();

        // Phase 4: Assign Roles
        _assignRoles(config);

        vm.stopBroadcast();

        // Phase 5: Output Verification Data
        _outputVerificationData(config);
    }

    function _loadConfig() internal view returns (DeployConfig memory) {
        return DeployConfig({
            ownerMultisig: vm.envAddress("OWNER_MULTISIG"),
            guardian: vm.envAddress("GUARDIAN_ADDRESS"),
            aiAgent: vm.envOr("AI_AGENT_ADDRESS", address(0)),
            assetToken: vm.envAddress("ASSET_TOKEN"),
            feeRecipient: vm.envOr("FEE_RECIPIENT", vm.envAddress("OWNER_MULTISIG")),
            chainId: block.chainid
        });
    }

    function _deployContracts(DeployConfig memory config) internal {
        ERC20 asset = ERC20(config.assetToken);

        riskEngine = new RiskEngine(config.ownerMultisig, authority);
        console.log("RiskEngine:", address(riskEngine));

        flashLoanEngine = new FlashLoanEngine(config.ownerMultisig, authority);
        console.log("FlashLoanEngine:", address(flashLoanEngine));

        feeVault =
            new FeeVault(asset, "Arbitrage Vault", "arbVAULT", config.feeRecipient, config.ownerMultisig, authority);
        console.log("FeeVault:", address(feeVault));

        ultimateArbitrageEngine = new UltimateArbitrageEngine(config.ownerMultisig, authority, address(feeVault));
        console.log("UltimateArbitrageEngine:", address(ultimateArbitrageEngine));

        quantumArbitrage =
            new QuantumArbitrage(config.ownerMultisig, authority, address(flashLoanEngine), address(riskEngine));
        console.log("QuantumArbitrage:", address(quantumArbitrage));

        mevProtector = new MEVProtector(config.ownerMultisig, authority);
        console.log("MEVProtector:", address(mevProtector));

        maxSecurityEngine = new MaximumSecurityEngine(config.ownerMultisig, authority);
        console.log("MaximumSecurityEngine:", address(maxSecurityEngine));

        crossChainRouter = new CrossChainRouter(config.ownerMultisig, authority);
        console.log("CrossChainRouter:", address(crossChainRouter));

        strategyOrchestrator = new StrategyOrchestrator(config.ownerMultisig, authority);
        console.log("StrategyOrchestrator:", address(strategyOrchestrator));

        executionTrigger = new ExecutionTrigger(config.ownerMultisig, authority);
        console.log("ExecutionTrigger:", address(executionTrigger));

        minimumCostExecutor = new MinimumCostExecutor(config.ownerMultisig, authority);
        console.log("MinimumCostExecutor:", address(minimumCostExecutor));

        strategyAnalytics = new StrategyAnalytics(config.ownerMultisig, authority);
        console.log("StrategyAnalytics:", address(strategyAnalytics));

        executionAnalytics = new ExecutionAnalytics(config.ownerMultisig, authority);
        console.log("ExecutionAnalytics:", address(executionAnalytics));

        intelligenceProcessor = new IntelligenceProcessor(config.ownerMultisig, authority);
        console.log("IntelligenceProcessor:", address(intelligenceProcessor));
    }

    function _wireAllCapabilities() internal {
        // ExecutionTrigger (6 capabilities)
        authority.setRoleCapability(
            Roles.EXECUTOR, address(executionTrigger), ExecutionTrigger.checkAndExecuteTriggers.selector, true
        );
        authority.setRoleCapability(
            Roles.UPDATER, address(executionTrigger), ExecutionTrigger.updateCooldown.selector, true
        );
        authority.setRoleCapability(
            Roles.UPDATER, address(executionTrigger), ExecutionTrigger.updateThreshold.selector, true
        );
        authority.setRoleCapability(
            Roles.UPDATER, address(executionTrigger), ExecutionTrigger.toggleTrigger.selector, true
        );
        authority.setRoleCapability(
            Roles.UPDATER, address(executionTrigger), ExecutionTrigger.removeTrigger.selector, true
        );
        authority.setRoleCapability(
            Roles.UPDATER, address(executionTrigger), ExecutionTrigger.addTrigger.selector, true
        );

        // FeeVault - P0 FIX: Separate deposit/withdraw (13 capabilities)
        authority.setRoleCapability(Roles.VAULT_DEPOSITOR, address(feeVault), FeeVault.deposit.selector, true);
        authority.setRoleCapability(Roles.ADMIN, address(feeVault), FeeVault.withdraw.selector, true);
        authority.setRoleCapability(Roles.ADMIN, address(feeVault), FeeVault.redeem.selector, true);
        authority.setRoleCapability(Roles.ARBITRAGE_MANAGER, address(feeVault), FeeVault.addRewards.selector, true);
        authority.setRoleCapability(Roles.FEE_UPDATER, address(feeVault), FeeVault.setDepositFee.selector, true);
        authority.setRoleCapability(Roles.FEE_UPDATER, address(feeVault), FeeVault.setWithdrawFee.selector, true);
        authority.setRoleCapability(Roles.FEE_UPDATER, address(feeVault), FeeVault.setPerformanceFee.selector, true);
        authority.setRoleCapability(Roles.UPDATER, address(feeVault), FeeVault.setFeeRecipient.selector, true);
        authority.setRoleCapability(Roles.UPDATER, address(feeVault), FeeVault.setRewardRate.selector, true);
        authority.setRoleCapability(Roles.ADMIN, address(feeVault), FeeVault.emergencyWithdraw.selector, true);
        authority.setRoleCapability(Roles.ADMIN, address(feeVault), FeeVault.pause.selector, true);
        authority.setRoleCapability(Roles.ADMIN, address(feeVault), FeeVault.unpause.selector, true);
        authority.setRoleCapability(Roles.GUARDIAN, address(feeVault), FeeVault.pause.selector, true);

        // QuantumArbitrage (9 capabilities)
        authority.setRoleCapability(
            Roles.ARBITRAGE_MANAGER, address(quantumArbitrage), QuantumArbitrage.executeArbitrage.selector, true
        );
        authority.setRoleCapability(
            Roles.ADMIN, address(quantumArbitrage), QuantumArbitrage.queueFlashLoanEngineUpdate.selector, true
        );
        authority.setRoleCapability(
            Roles.ADMIN, address(quantumArbitrage), QuantumArbitrage.queueRiskEngineUpdate.selector, true
        );
        authority.setRoleCapability(
            Roles.ADMIN, address(quantumArbitrage), QuantumArbitrage.executeFlashLoanEngineUpdate.selector, true
        );
        authority.setRoleCapability(
            Roles.ADMIN, address(quantumArbitrage), QuantumArbitrage.executeRiskEngineUpdate.selector, true
        );
        authority.setRoleCapability(
            Roles.ADMIN, address(quantumArbitrage), QuantumArbitrage.cancelPendingFlashLoanUpdate.selector, true
        );
        authority.setRoleCapability(
            Roles.ADMIN, address(quantumArbitrage), QuantumArbitrage.cancelPendingRiskUpdate.selector, true
        );
        authority.setRoleCapability(
            Roles.RISK_MANAGER, address(quantumArbitrage), QuantumArbitrage.setMinRiskScore.selector, true
        );
        authority.setRoleCapability(
            Roles.RISK_MANAGER, address(quantumArbitrage), QuantumArbitrage.setMaxExecutionsPerBlock.selector, true
        );

        // RiskEngine (5 capabilities)
        authority.setRoleCapability(
            Roles.RISK_MANAGER, address(riskEngine), RiskEngine.setTokenRiskScore.selector, true
        );
        authority.setRoleCapability(Roles.RISK_MANAGER, address(riskEngine), RiskEngine.setPairRiskScore.selector, true);
        authority.setRoleCapability(Roles.RISK_MANAGER, address(riskEngine), RiskEngine.setRiskParams.selector, true);
        authority.setRoleCapability(
            Roles.RISK_MANAGER, address(riskEngine), RiskEngine.setGlobalRiskMultiplier.selector, true
        );
        authority.setRoleCapability(
            Roles.RISK_MANAGER, address(riskEngine), RiskEngine.batchSetTokenRiskScores.selector, true
        );

        // CrossChainRouter - P0 FIX: timelock bindings (5 capabilities)
        authority.setRoleCapability(
            Roles.CROSSCHAIN_OPERATOR, address(crossChainRouter), CrossChainRouter.executeCrossChainTrade.selector, true
        );
        authority.setRoleCapability(
            Roles.ADMIN, address(crossChainRouter), CrossChainRouter.queueChainConfig.selector, true
        );
        authority.setRoleCapability(
            Roles.ADMIN, address(crossChainRouter), CrossChainRouter.executeChainConfig.selector, true
        );
        authority.setRoleCapability(
            Roles.ADMIN, address(crossChainRouter), CrossChainRouter.cancelPendingConfig.selector, true
        );
        authority.setRoleCapability(
            Roles.UPDATER, address(crossChainRouter), CrossChainRouter.setDailyLimit.selector, true
        );

        // StrategyOrchestrator (5 capabilities)
        authority.setRoleCapability(
            Roles.STRATEGY_MANAGER, address(strategyOrchestrator), StrategyOrchestrator.addStrategy.selector, true
        );
        authority.setRoleCapability(
            Roles.STRATEGY_MANAGER, address(strategyOrchestrator), StrategyOrchestrator.removeStrategy.selector, true
        );
        authority.setRoleCapability(
            Roles.STRATEGY_MANAGER, address(strategyOrchestrator), StrategyOrchestrator.updateStrategy.selector, true
        );
        authority.setRoleCapability(
            Roles.STRATEGY_MANAGER, address(strategyOrchestrator), StrategyOrchestrator.toggleStrategy.selector, true
        );
        authority.setRoleCapability(
            Roles.ARBITRAGE_MANAGER,
            address(strategyOrchestrator),
            StrategyOrchestrator.executeStrategyFlow.selector,
            true
        );

        // MEVProtector - P0 FIX: commit + whitelist bindings (6 capabilities)
        authority.setRoleCapability(Roles.EXECUTOR, address(mevProtector), MEVProtector.commitExecution.selector, true);
        authority.setRoleCapability(
            Roles.EXECUTOR, address(mevProtector), MEVProtector.executeProtectedArbitrage.selector, true
        );
        authority.setRoleCapability(
            Roles.WHITELIST_ADMIN, address(mevProtector), MEVProtector.setTargetWhitelist.selector, true
        );
        authority.setRoleCapability(
            Roles.WHITELIST_ADMIN, address(mevProtector), MEVProtector.setSelectorWhitelist.selector, true
        );
        authority.setRoleCapability(
            Roles.WHITELIST_ADMIN, address(mevProtector), MEVProtector.batchSetTargetWhitelist.selector, true
        );
        authority.setRoleCapability(
            Roles.WHITELIST_ADMIN, address(mevProtector), MEVProtector.batchSetSelectorWhitelist.selector, true
        );

        // MaxSecurityEngine (5 capabilities)
        authority.setRoleCapability(
            Roles.EXECUTOR, address(maxSecurityEngine), MaximumSecurityEngine.executeWithMaximumSecurity.selector, true
        );
        authority.setRoleCapability(
            Roles.RISK_MANAGER, address(maxSecurityEngine), MaximumSecurityEngine.setSecurityConfig.selector, true
        );
        authority.setRoleCapability(
            Roles.RISK_MANAGER, address(maxSecurityEngine), MaximumSecurityEngine.setUserSecurityScore.selector, true
        );
        authority.setRoleCapability(
            Roles.WHITELIST_ADMIN, address(maxSecurityEngine), MaximumSecurityEngine.setTargetWhitelist.selector, true
        );
        authority.setRoleCapability(
            Roles.WHITELIST_ADMIN, address(maxSecurityEngine), MaximumSecurityEngine.setSelectorWhitelist.selector, true
        );

        // FlashLoanEngine - P0 FIX: DEX whitelist binding (7 capabilities)
        authority.setRoleCapability(
            Roles.ARBITRAGE_MANAGER, address(flashLoanEngine), FlashLoanEngine.executeFlashLoanArbitrage.selector, true
        );
        authority.setRoleCapability(Roles.ADMIN, address(flashLoanEngine), FlashLoanEngine.addProvider.selector, true);
        authority.setRoleCapability(
            Roles.ADMIN, address(flashLoanEngine), FlashLoanEngine.removeProvider.selector, true
        );
        authority.setRoleCapability(
            Roles.ADMIN, address(flashLoanEngine), FlashLoanEngine.updateProvider.selector, true
        );
        authority.setRoleCapability(
            Roles.WHITELIST_ADMIN, address(flashLoanEngine), FlashLoanEngine.setDexRouterWhitelist.selector, true
        );
        authority.setRoleCapability(
            Roles.WHITELIST_ADMIN, address(flashLoanEngine), FlashLoanEngine.setExecutorStatus.selector, true
        );
        authority.setRoleCapability(
            Roles.UPDATER, address(flashLoanEngine), FlashLoanEngine.setSlippageLimits.selector, true
        );

        // MinimumCostExecutor (4 capabilities)
        authority.setRoleCapability(
            Roles.EXECUTOR, address(minimumCostExecutor), MinimumCostExecutor.executeWithMinimumCost.selector, true
        );
        authority.setRoleCapability(
            Roles.UPDATER, address(minimumCostExecutor), MinimumCostExecutor.setMaxCostPercentage.selector, true
        );
        authority.setRoleCapability(
            Roles.UPDATER, address(minimumCostExecutor), MinimumCostExecutor.setDefaultPriorityFee.selector, true
        );
        authority.setRoleCapability(
            Roles.UPDATER, address(minimumCostExecutor), MinimumCostExecutor.setMaxGasPrice.selector, true
        );

        // UltimateArbitrageEngine (5 capabilities)
        authority.setRoleCapability(
            Roles.ARBITRAGE_MANAGER,
            address(ultimateArbitrageEngine),
            UltimateArbitrageEngine.executeArbitrage.selector,
            true
        );
        authority.setRoleCapability(
            Roles.WHITELIST_ADMIN,
            address(ultimateArbitrageEngine),
            UltimateArbitrageEngine.setFlashLoanPoolWhitelist.selector,
            true
        );
        authority.setRoleCapability(
            Roles.WHITELIST_ADMIN,
            address(ultimateArbitrageEngine),
            UltimateArbitrageEngine.setExecutorAuthorization.selector,
            true
        );
        authority.setRoleCapability(
            Roles.ADMIN, address(ultimateArbitrageEngine), UltimateArbitrageEngine.setFeeVault.selector, true
        );
        authority.setRoleCapability(
            Roles.FEE_UPDATER,
            address(ultimateArbitrageEngine),
            UltimateArbitrageEngine.setPerformanceFee.selector,
            true
        );

        // Analytics (4 capabilities)
        authority.setRoleCapability(
            Roles.EXECUTOR, address(strategyAnalytics), StrategyAnalytics.recordTrade.selector, true
        );
        authority.setRoleCapability(
            Roles.ADMIN, address(strategyAnalytics), StrategyAnalytics.resetMetrics.selector, true
        );
        authority.setRoleCapability(
            Roles.EXECUTOR, address(executionAnalytics), ExecutionAnalytics.recordExecution.selector, true
        );

        // IntelligenceProcessor (3 capabilities)
        authority.setRoleCapability(
            Roles.STRATEGY_MANAGER, address(intelligenceProcessor), IntelligenceProcessor.addOpportunity.selector, true
        );
        authority.setRoleCapability(
            Roles.EXECUTOR, address(intelligenceProcessor), IntelligenceProcessor.markProcessed.selector, true
        );
        authority.setRoleCapability(
            Roles.UPDATER,
            address(intelligenceProcessor),
            IntelligenceProcessor.clearExpiredOpportunities.selector,
            true
        );

        console.log("Wired 67 role capabilities");
    }

    function _assignRoles(DeployConfig memory config) internal {
        // ADMIN role for multisig
        authority.setUserRole(config.ownerMultisig, Roles.ADMIN, true);
        authority.setUserRole(config.ownerMultisig, Roles.WHITELIST_ADMIN, true);
        console.log("Assigned ADMIN + WHITELIST_ADMIN to multisig");

        // GUARDIAN role for emergency EOA
        authority.setUserRole(config.guardian, Roles.GUARDIAN, true);
        console.log("Assigned GUARDIAN to:", config.guardian);

        // AI Agent roles (minimal privilege set per audit spec)
        if (config.aiAgent != address(0)) {
            authority.setUserRole(config.aiAgent, Roles.EXECUTOR, true);
            authority.setUserRole(config.aiAgent, Roles.CROSSCHAIN_OPERATOR, true);
            authority.setUserRole(config.aiAgent, Roles.VAULT_DEPOSITOR, true);
            console.log("Assigned EXECUTOR + CROSSCHAIN_OPERATOR + VAULT_DEPOSITOR to AI agent");
            console.log("AI agent CANNOT: withdraw, pause, modify fees, manage whitelists");
        }
    }

    function _outputVerificationData(DeployConfig memory config) internal view {
        console.log("");
        console.log("=== Verification Commands ===");
        console.log("");
        console.log("forge verify-contract", address(authority), "RolesAuthority --chain", config.chainId);
        console.log("forge verify-contract", address(feeVault), "FeeVault --chain", config.chainId);
        console.log("forge verify-contract", address(mevProtector), "MEVProtector --chain", config.chainId);
        console.log("forge verify-contract", address(flashLoanEngine), "FlashLoanEngine --chain", config.chainId);
        console.log("forge verify-contract", address(crossChainRouter), "CrossChainRouter --chain", config.chainId);
        console.log("forge verify-contract", address(riskEngine), "RiskEngine --chain", config.chainId);
        console.log("");
        console.log("=== Post-Deployment Checklist ===");
        console.log("1. Initialize dead shares: feeVault.initializeDeadShares()");
        console.log("2. Add flash loan providers via ADMIN");
        console.log("3. Set initial risk scores via RISK_MANAGER");
        console.log("4. Configure chain bridges via ADMIN timelock");
        console.log("5. Whitelist DEX routers via WHITELIST_ADMIN");
        console.log("6. Test guardian pause functionality");
        console.log("7. Verify AI agent cannot withdraw from vault");
    }
}
