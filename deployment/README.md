# Deployment Guide

## Prerequisites

1. **Gnosis Safe Multisig** (3-of-5 recommended)
   - Deploy at [safe.global](https://safe.global)
   - Save the Safe address as `OWNER_SAFE`

2. **AI Agent Wallet**
   - Generate a fresh EOA for the autonomous agent
   - Fund with sufficient ETH for gas
   - Save as `AI_AGENT`

3. **Guardian EOA**
   - Dedicated EOA for emergency pause (fast response time)
   - Should be separate from Safe signers
   - Save as `GUARDIAN`

4. **Asset Token**
   - USDC: `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` (Ethereum)
   - WETH: `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` (Ethereum)

## Environment Setup

```bash
# Create .env file
cat > .env << 'ENVEOF'
# Required
OWNER_SAFE=0x...          # Gnosis Safe multisig address
AI_AGENT=0x...            # AI execution agent EOA
GUARDIAN=0x...            # Emergency pause EOA
ASSET_TOKEN=0x...         # USDC/WETH address

# Optional (defaults to OWNER_SAFE)
FEE_RECIPIENT=0x...       # Protocol fee recipient

# RPC & Keys
RPC_URL=https://...       # Mainnet/Arbitrum/Base RPC
PRIVATE_KEY=0x...         # Deployer private key
ETHERSCAN_API_KEY=...     # For verification
ENVEOF
```

## Deployment Commands

### Testnet (Sepolia)
```bash
source .env
forge script script/DeployMainnet.s.sol:DeployMainnet \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify \
  -vvvv
```

### Mainnet
```bash
source .env
forge script script/DeployMainnet.s.sol:DeployMainnet \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify \
  --slow \
  -vvvv
```

### Dry Run (No Broadcast)
```bash
source .env
forge script script/DeployMainnet.s.sol:DeployMainnet \
  --rpc-url $RPC_URL \
  -vvvv
```

## Post-Deployment Checklist

### 1. Verify All Contracts
```bash
# If auto-verify failed, manually verify:
forge verify-contract <ADDRESS> <CONTRACT> \
  --chain-id <CHAIN_ID> \
  --constructor-args $(cast abi-encode "constructor(address,address)" <ARG1> <ARG2>)
```

### 2. Initialize FeeVault Dead Shares
```bash
# From OWNER_SAFE, call initializeDeadShares()
# This mints 1000 shares to dead address for inflation attack protection
cast send $FEE_VAULT "initializeDeadShares()" --private-key $DEPLOYER_KEY
```

### 3. Configure Flash Loan Providers
```bash
# Add Aave V3
cast send $FLASH_LOAN_ENGINE "addProvider(bytes32,address,uint256)" \
  $(cast keccak "AAVE_V3") \
  0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2 \
  9 \
  --private-key $OWNER_KEY
```

### 4. Configure Risk Parameters
```bash
# Set base token risk scores
cast send $RISK_ENGINE "batchSetTokenRiskScores(address[],uint256[])" \
  "[0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2]" \
  "[10,15]" \
  --private-key $RISK_MANAGER_KEY
```

### 5. Whitelist DEX Routers
```bash
# Uniswap V3
cast send $FLASH_LOAN_ENGINE "setDexRouterWhitelist(address,bool)" \
  0xE592427A0AEce92De3Edee1F18E0157C05861564 \
  true \
  --private-key $WHITELIST_ADMIN_KEY
```

## Role Assignment Reference

| Role | ID | Assigned To | Capabilities |
|------|-----|-------------|--------------|
| ADMIN | 0 | OWNER_SAFE | All config, emergency, providers |
| EXECUTOR | 1 | AI_AGENT | Execute, commit, record |
| ARBITRAGE_MANAGER | 2 | (assign as needed) | Flash loans, strategy flows |
| RISK_MANAGER | 3 | (assign as needed) | Risk scores, circuit breakers |
| CROSSCHAIN_OPERATOR | 4 | AI_AGENT | Bridge execution |
| STRATEGY_MANAGER | 5 | (assign as needed) | Strategy CRUD |
| UPDATER | 6 | (assign as needed) | Parameters, limits |
| VAULT_DEPOSITOR | 7 | AI_AGENT | Deposit only |
| GUARDIAN | 8 | GUARDIAN EOA | Emergency pause |
| FEE_UPDATER | 9 | (assign as needed) | Fee rates only |
| WHITELIST_ADMIN | 10 | OWNER_SAFE | Target/selector whitelists |

## Emergency Procedures

### Pause All Operations (Guardian)
```bash
cast send $FEE_VAULT "pause()" --private-key $GUARDIAN_KEY
```

### Revoke AI Agent (Multisig)
```bash
# Execute via Safe Transaction Builder
cast calldata "setUserRole(address,uint8,bool)" $AI_AGENT 1 false
cast calldata "setUserRole(address,uint8,bool)" $AI_AGENT 4 false
cast calldata "setUserRole(address,uint8,bool)" $AI_AGENT 7 false
```

### Emergency Withdraw (Multisig)
```bash
cast send $FEE_VAULT "emergencyWithdraw(address)" $SAFE_ADDRESS --private-key $OWNER_KEY
```

## Verification URLs

After deployment, contracts will be verified at:
- Etherscan: `https://etherscan.io/address/<CONTRACT_ADDRESS>#code`
- Arbiscan: `https://arbiscan.io/address/<CONTRACT_ADDRESS>#code`
- Basescan: `https://basescan.org/address/<CONTRACT_ADDRESS>#code`
