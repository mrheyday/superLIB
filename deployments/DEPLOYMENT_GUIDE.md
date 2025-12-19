# Production Deployment Guide

## Overview

This guide covers the complete deployment process for the DeFi Arbitrage Protocol with Solmate RolesAuthority access control. The deployment implements all security fixes from audit specification v1.1.

## Pre-Deployment Requirements

### Infrastructure

1. **Gnosis Safe Multisig** (3-of-5 recommended)
   - Create at [safe.global](https://safe.global)
   - Add 5 signers with hardware wallets
   - Set threshold to 3 signatures

2. **Guardian EOA**
   - Dedicated hot wallet for emergency pause
   - Should be monitored 24/7
   - Only has GUARDIAN role (pause capability)

3. **AI Agent Wallet** (optional)
   - Hardware wallet or secure enclave
   - Minimal role set: EXECUTOR, CROSSCHAIN_OPERATOR, VAULT_DEPOSITOR
   - Cannot withdraw, modify fees, or manage whitelists

### Environment Setup

```bash
# Copy environment template
cp deployments/.env.example .env

# Fill in required values
nano .env
```

### Token Addresses by Network

| Network   | USDC                                       | WETH                                       |
|-----------|--------------------------------------------|--------------------------------------------|
| Mainnet   | 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 | 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 |
| Arbitrum  | 0xaf88d065e77c8cC2239327C5EDb3A432268e5831 | 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1 |
| Base      | 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 | 0x4200000000000000000000000000000000000006 |

## Deployment Commands

### Mainnet Deployment

```bash
# Dry run (simulation)
forge script script/DeployProduction.s.sol:DeployProduction \
  --rpc-url $MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY \
  -vvvv

# Live deployment
forge script script/DeployProduction.s.sol:DeployProduction \
  --rpc-url $MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  -vvvv
```

### Arbitrum Deployment

```bash
forge script script/DeployProduction.s.sol:DeployProduction \
  --rpc-url $ARBITRUM_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ARBISCAN_API_KEY \
  -vvvv
```

### Base Deployment

```bash
forge script script/DeployProduction.s.sol:DeployProduction \
  --rpc-url $BASE_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $BASESCAN_API_KEY \
  -vvvv
```

## Post-Deployment Checklist

### 1. Initialize Vault Dead Shares

```solidity
// From multisig - prevents inflation attacks
feeVault.initializeDeadShares();
```

### 2. Add Flash Loan Providers

```solidity
// From ADMIN role
flashLoanEngine.addProvider(
    keccak256("AAVE_V3"),
    0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2, // Aave V3 Pool
    9 // 0.09% fee in basis points
);
```

### 3. Configure Risk Scores

```solidity
// From RISK_MANAGER role
riskEngine.batchSetTokenRiskScores(tokens, scores);
```

### 4. Whitelist DEX Routers

```solidity
// From WHITELIST_ADMIN role (elevated permission)
flashLoanEngine.setDexRouterWhitelist(UNISWAP_V3_ROUTER, true);
flashLoanEngine.setDexRouterWhitelist(SUSHISWAP_ROUTER, true);
```

### 5. Configure Cross-Chain Bridges

```solidity
// From ADMIN role (uses timelock)
crossChainRouter.queueChainConfig(
    42161,           // Arbitrum chain ID
    bridgeAddress,   // Bridge contract
    1 hours,         // Min delay
    100_000e6,       // Daily limit (100k USDC)
    true             // Enabled
);

// Wait for timelock, then execute
crossChainRouter.executeChainConfig(configHash);
```

## Security Verification

### Verify AI Agent Cannot Withdraw

```solidity
// This should revert
vm.prank(aiAgent);
feeVault.withdraw(1e18, aiAgent, aiAgent); // MUST FAIL
```

### Verify Guardian Can Pause

```solidity
// This should succeed
vm.prank(guardian);
feeVault.pause(); // MUST SUCCEED
```

### Verify Role Separation

```solidity
// Executor cannot modify whitelists
vm.prank(executor);
mevProtector.setTargetWhitelist(target, true); // MUST FAIL

// Fee updater cannot pause
vm.prank(feeUpdater);
feeVault.pause(); // MUST FAIL
```

## Role Matrix Reference

| Role ID | Role Name           | Purpose                                    |
|---------|---------------------|--------------------------------------------|
| 0       | ADMIN               | Contract upgrades, emergency, providers    |
| 1       | EXECUTOR            | Execute trades, record analytics           |
| 2       | ARBITRAGE_MANAGER   | Flash loans, strategy flows                |
| 3       | RISK_MANAGER        | Risk scores, circuit breakers              |
| 4       | CROSSCHAIN_OPERATOR | Bridge execution only                      |
| 5       | STRATEGY_MANAGER    | Strategy CRUD                              |
| 6       | UPDATER             | Parameters, cooldowns, limits              |
| 7       | VAULT_DEPOSITOR     | Deposit only (AI agent role)               |
| 8       | GUARDIAN            | Emergency pause only                       |
| 9       | FEE_UPDATER         | Fee rates only                             |
| 10      | WHITELIST_ADMIN     | Target/selector/DEX whitelists (elevated)  |

## Emergency Procedures

### Guardian Pause

If suspicious activity detected:

```solidity
// Guardian EOA calls directly
feeVault.pause();
```

### AI Agent Revocation

If AI agent compromised:

```solidity
// From ADMIN multisig
authority.setUserRole(aiAgent, Roles.EXECUTOR, false);
authority.setUserRole(aiAgent, Roles.CROSSCHAIN_OPERATOR, false);
authority.setUserRole(aiAgent, Roles.VAULT_DEPOSITOR, false);
```

### Full Protocol Pause

```solidity
// From ADMIN multisig - pause all entry points
feeVault.pause();
// Other contracts should check feeVault.paused() before execution
```

## Contract Addresses

After deployment, record addresses in `deployments/<network>-addresses.json`:

```json
{
  "chainId": 1,
  "deployedAt": "2024-XX-XX",
  "contracts": {
    "authority": "0x...",
    "feeVault": "0x...",
    "mevProtector": "0x...",
    "flashLoanEngine": "0x...",
    "crossChainRouter": "0x...",
    "riskEngine": "0x...",
    "strategyOrchestrator": "0x...",
    "quantumArbitrage": "0x...",
    "ultimateArbitrageEngine": "0x...",
    "executionTrigger": "0x...",
    "minimumCostExecutor": "0x...",
    "strategyAnalytics": "0x...",
    "executionAnalytics": "0x...",
    "intelligenceProcessor": "0x..."
  },
  "roles": {
    "admin": "0x... (multisig)",
    "guardian": "0x... (EOA)",
    "aiAgent": "0x... (optional)"
  }
}
```
