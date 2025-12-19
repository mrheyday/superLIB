// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Roles} from "../src/roles/Roles.sol";
import {Script, console} from "forge-std/Script.sol";
import {Authority} from "superlib/auth/Auth.sol";
import {RolesAuthority} from "superlib/auth/RolesAuthority.sol";
import {ERC20} from "superlib/core/ERC20.sol";

import {CrossChainRouter} from "../src/CrossChainRouter.sol";
import {ExecutionAnalytics} from "../src/ExecutionAnalytics.sol";
import {ExecutionTrigger} from "../src/ExecutionTrigger.sol";
import {FeeVault} from "../src/FeeVault.sol";
import {FlashLoanEngine} from "../src/FlashLoanEngine.sol";
import {IntelligenceProcessor} from "../src/IntelligenceProcessor.sol";
import {MEVProtector} from "../src/MEVProtector.sol";
import {MaximumSecurityEngine} from "../src/MaximumSecurityEngine.sol";
import {MinimumCostExecutor} from "../src/MinimumCostExecutor.sol";
import {QuantumArbitrage} from "../src/QuantumArbitrage.sol";
import {RiskEngine} from "../src/RiskEngine.sol";
import {StrategyAnalytics} from "../src/StrategyAnalytics.sol";
import {StrategyOrchestrator} from "../src/StrategyOrchestrator.sol";
import {UltimateArbitrageEngine} from "../src/UltimateArbitrageEngine.sol";

/// @title DeployWithRoles
/// @notice Production deployment with corrected Solmate RolesAuthority wiring
contract DeployWithRoles is Script {

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

    function run() external {
        address OWNER = vm.envOr("OWNER_ADDRESS", msg.sender);
        address AI_AGENT = vm.envOr("AI_AGENT_ADDRESS", address(0));
        address ASSET_TOKEN = vm.envOr("ASSET_TOKEN", address(0));
        address FEE_RECIPIENT = vm.envOr("FEE_RECIPIENT", OWNER);

        vm.startBroadcast();

        authority = new RolesAuthority(OWNER, Authority(address(0)));
        console.log("RolesAuthority:", address(authority));

        ERC20 assetToken;
        if (ASSET_TOKEN == address(0)) {
            assetToken = ERC20(address(new MockERC20("Mock USDC", "mUSDC", 6)));
        } else {
            assetToken = ERC20(ASSET_TOKEN);
        }

        riskEngine = new RiskEngine(OWNER, authority);
        flashLoanEngine = new FlashLoanEngine(OWNER, authority);
        feeVault = new FeeVault(assetToken, "Arbitrage Vault", "arbVAULT", FEE_RECIPIENT, OWNER, authority);
        ultimateArbitrageEngine = new UltimateArbitrageEngine(OWNER, authority, address(feeVault));
        quantumArbitrage = new QuantumArbitrage(OWNER, authority, address(flashLoanEngine), address(riskEngine));
        mevProtector = new MEVProtector(OWNER, authority);
        maxSecurityEngine = new MaximumSecurityEngine(OWNER, authority);
        crossChainRouter = new CrossChainRouter(OWNER, authority);
        strategyOrchestrator = new StrategyOrchestrator(OWNER, authority);
        executionTrigger = new ExecutionTrigger(OWNER, authority);
        minimumCostExecutor = new MinimumCostExecutor(OWNER, authority);
        strategyAnalytics = new StrategyAnalytics(OWNER, authority);
        executionAnalytics = new ExecutionAnalytics(OWNER, authority);
        intelligenceProcessor = new IntelligenceProcessor(OWNER, authority);

        _wireAllRoles();

        if (AI_AGENT != address(0)) {
            authority.setUserRole(AI_AGENT, Roles.EXECUTOR, true);
            authority.setUserRole(AI_AGENT, Roles.CROSSCHAIN_OPERATOR, true);
            authority.setUserRole(AI_AGENT, Roles.VAULT_DEPOSITOR, true);
        }

        vm.stopBroadcast();
        console.log("Deployment complete");
    }

    function _wireAllRoles() internal {
        // ExecutionTrigger
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

        // FeeVault - P0 FIX: Separate deposit/withdraw
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

        // QuantumArbitrage
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

        // RiskEngine
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

        // CrossChainRouter - P0 FIX: timelock bindings
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

        // StrategyOrchestrator
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

        // MEVProtector - P0 FIX: commit + whitelist bindings
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

        // MaxSecurityEngine
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

        // FlashLoanEngine - P0 FIX: DEX whitelist binding
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

        // MinimumCostExecutor
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
        authority.setRoleCapability(
            Roles.ADMIN, address(minimumCostExecutor), MinimumCostExecutor.addGasRefund.selector, true
        );

        // UltimateArbitrageEngine
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

        // Analytics
        authority.setRoleCapability(
            Roles.EXECUTOR, address(strategyAnalytics), StrategyAnalytics.recordTrade.selector, true
        );
        authority.setRoleCapability(
            Roles.ADMIN, address(strategyAnalytics), StrategyAnalytics.resetMetrics.selector, true
        );
        authority.setRoleCapability(
            Roles.EXECUTOR, address(executionAnalytics), ExecutionAnalytics.recordExecution.selector, true
        );
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
    }

}

contract MockERC20 is ERC20 {

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) ERC20(name, symbol, decimals_) {
        _mint(msg.sender, 1_000_000 * 10 ** decimals_);
    }

    function mint(
        address to,
        uint256 amount
    ) external {
        _mint(to, amount);
    }

}
