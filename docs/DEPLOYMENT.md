# Deployment Guide

This guide provides step-by-step instructions for deploying the DeFi Arbitrage Protocol to various networks. Follow the appropriate section based on your target environment.

## Prerequisites

Before beginning deployment, ensure you have the following tools and resources available.

### Required Software

Foundry must be installed on your system. Install it using the official installer:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Verify the installation:

```bash
forge --version
```

### Required Resources

You will need an Ethereum wallet with sufficient ETH for gas costs. For mainnet deployment, we recommend at least 0.5 ETH. You will also need RPC endpoints for your target networks, which can be obtained from providers such as Alchemy, Infura, or QuickNode. For contract verification, obtain an API key from Etherscan or the relevant block explorer.

### Wallet Security

For production deployments, we strongly recommend using a hardware wallet or multisig. Never store production private keys in plain text files. Consider using a secrets manager or hardware security module for key management.

## Environment Setup

Create a `.env` file in the project root directory with your configuration:

```bash
# Private key for deployment transactions
PRIVATE_KEY=0x...

# Admin address (use multisig for production)
ADMIN_ADDRESS=0x...

# Address to receive protocol fees
FEE_RECIPIENT=0x...

# RPC endpoints
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
ARBITRUM_RPC_URL=https://arb-mainnet.g.alchemy.com/v2/YOUR_KEY

# Block explorer API keys for verification
ETHERSCAN_API_KEY=your_key
ARBISCAN_API_KEY=your_key

# Set to false for production
IS_TESTNET=true
```

Load the environment variables:

```bash
source .env
```

## Testnet Deployment

Testnet deployment is recommended for initial testing and integration verification. The deployment includes mock tokens for testing without real assets.

### Step 1: Compile Contracts

```bash
forge build
```

Verify compilation succeeds without errors. Warnings about unused variables or function visibility can be ignored for initial deployment.

### Step 2: Run Test Suite

Execute the test suite to verify contract behavior:

```bash
forge test
```

Ensure critical security tests pass before proceeding.

### Step 3: Deploy to Sepolia

Execute the full deployment script:

```bash
forge script script/DeployAll.s.sol:DeployAll \
    --rpc-url $SEPOLIA_RPC_URL \
    --broadcast \
    --verify \
    -vvv
```

The `-vvv` flag provides verbose output showing each transaction. The script will output deployed contract addresses upon completion.

### Step 4: Record Addresses

Save the deployed addresses from the console output. You will need these for configuration and integration:

```
FlashLoanEngine: 0x...
UltimateArbitrageEngine: 0x...
RiskEngine: 0x...
QuantumArbitrage: 0x...
MEVProtector: 0x...
MaximumSecurityEngine: 0x...
CrossChainRouter: 0x...
FeeVault: 0x...
MockUSDC: 0x...
MockWETH: 0x...
```

### Step 5: Verify Deployment

Check each contract on Sepolia Etherscan to confirm verification and initial state.

## Production Deployment

Production deployment requires additional care and security considerations. Follow these steps carefully.

### Pre-Deployment Checklist

Before deploying to mainnet, verify the following items are complete:

1. All tests pass including fuzz tests with extended runs
2. Admin address is a multisig wallet with appropriate signers
3. Fee recipient address is correct and accessible
4. RPC endpoints are reliable production-grade services
5. Sufficient ETH is available for deployment gas costs
6. Team is available to monitor deployment in real-time

### Step 1: Final Audit Verification

Run the extended test suite:

```bash
FOUNDRY_FUZZ_RUNS=1000 forge test -vvv
```

Review any failures or warnings before proceeding.

### Step 2: Deploy Core Infrastructure

Deploy the core contracts without mock tokens:

```bash
forge script script/DeployCore.s.sol:DeployCore \
    --rpc-url $MAINNET_RPC_URL \
    --broadcast \
    --verify \
    --slow \
    -vvv
```

The `--slow` flag adds delays between transactions to ensure proper sequencing on mainnet.

### Step 3: Deploy FeeVault

The FeeVault requires specifying the underlying asset. For USDC on mainnet:

```bash
USDC_MAINNET=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48

forge script script/DeployCore.s.sol:DeployFeeVault \
    --sig "run(address)" \
    $USDC_MAINNET \
    --rpc-url $MAINNET_RPC_URL \
    --broadcast \
    --verify
```

### Step 4: Configure Whitelists

Configure approved DEX routers and flash loan pools. This example uses Uniswap V3 router and Aave V3 pool:

```bash
FLASH_LOAN_ENGINE=0x... # Address from Step 2
UNISWAP_V3_ROUTER=0xE592427A0AEce92De3Edee1F18E0157C05861564
AAVE_V3_POOL=0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2

forge script script/DeployCore.s.sol:ConfigureWhitelists \
    --sig "run(address,address[],address[])" \
    $FLASH_LOAN_ENGINE \
    "[$UNISWAP_V3_ROUTER]" \
    "[$AAVE_V3_POOL]" \
    --rpc-url $MAINNET_RPC_URL \
    --broadcast
```

### Step 5: Configure Cross-Chain Routes

Queue chain configurations for each supported network. Due to the 24-hour timelock, this must be done in advance of operations:

```bash
# This requires direct contract interaction via cast or etherscan
# Queue Polygon configuration
cast send $CROSS_CHAIN_ROUTER \
    "queueChainConfig(uint256,address,uint256,uint256,bool)" \
    137 \
    $POLYGON_BRIDGE_ADDRESS \
    1000000 \
    1000000000000 \
    true \
    --rpc-url $MAINNET_RPC_URL \
    --private-key $PRIVATE_KEY
```

Wait 24 hours, then execute:

```bash
cast send $CROSS_CHAIN_ROUTER \
    "executeChainConfig(uint256)" \
    137 \
    --rpc-url $MAINNET_RPC_URL \
    --private-key $PRIVATE_KEY
```

## Post-Deployment Verification

After deployment, perform these verification steps.

### Contract State Verification

For each contract, verify the following on the block explorer:

1. Contract is verified and source code matches repository
2. Owner address matches expected admin multisig
3. Initial state variables are correctly set
4. No unexpected transactions in contract history

### Functional Verification

Test basic operations with small amounts:

1. Deposit into FeeVault and verify share receipt
2. Queue a configuration change and verify timelock
3. Attempt an unauthorized operation and verify rejection

### Monitoring Setup

Configure monitoring for these events:

```solidity
event TargetWhitelisted(address indexed target, bool whitelisted);
event ChainConfigQueued(uint256 indexed chainId, address bridge, uint256 effectiveTime);
event FlashLoanEngineUpdateQueued(address newEngine, uint256 effectiveTime);
event ThreatDetected(address indexed target, string reason);
event FeesCollected(address indexed recipient, uint256 amount);
```

## Upgrade Procedures

The contracts are intentionally non-upgradeable for security. To deploy updates, follow this procedure.

### Deploying Updated Contracts

1. Deploy the new contract version
2. Queue engine update in dependent contracts (24-hour timelock)
3. After timelock expires, execute the update
4. Verify new contract integration
5. Deprecate old contract by removing authorizations

### Migration Example

To migrate to a new FlashLoanEngine:

```bash
# Deploy new engine
forge script script/DeployCore.s.sol:DeployCore ...

# Queue update in QuantumArbitrage
cast send $QUANTUM_ARBITRAGE \
    "queueFlashLoanEngineUpdate(address)" \
    $NEW_FLASH_LOAN_ENGINE \
    --rpc-url $MAINNET_RPC_URL \
    --private-key $PRIVATE_KEY

# Wait 24 hours, then execute
cast send $QUANTUM_ARBITRAGE \
    "executeFlashLoanEngineUpdate()" \
    --rpc-url $MAINNET_RPC_URL \
    --private-key $PRIVATE_KEY
```

## Troubleshooting

### Common Issues

**Transaction Reverts During Deployment**: Check that the deployer has sufficient ETH for gas. Verify RPC endpoint is responsive. Review transaction error message for specific revert reason.

**Contract Verification Fails**: Ensure compiler version matches `foundry.toml` settings. Verify constructor arguments are correctly encoded. Check that all imported contracts are included in verification.

**Timelock Blocks Execution**: Configuration changes require waiting the full timelock period. The `effectiveTime` returned from queue transactions indicates when execution becomes possible.

### Getting Help

For deployment issues, review the deployment transaction on the block explorer for specific error messages. Check the Foundry documentation for script-related problems. For protocol-specific questions, refer to the contract documentation in this repository.
