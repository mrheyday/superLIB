# Superlib Arbitrage Protocol

A production-grade DeFi arbitrage protocol built on [Superlib](https://github.com/superlib/superlib) with Solmate-style RolesAuthority access control. Implements comprehensive security patterns derived from a formal Trinity security audit.

## Overview

This protocol enables automated cross-chain arbitrage execution with:

- **Flash loan integration** (Aave, Balancer, Uniswap)
- **MEV protection** via commit-reveal schemes
- **Cross-chain routing** with timelocked configuration
- **ERC4626 fee vault** with inflation attack protection
- **AI agent support** with minimal privilege constraints

## Security Model

The protocol uses Solmate's `RolesAuthority` for capability-based access control with 11 granular roles:

| Role | ID | Purpose |
|------|----|---------|
| ADMIN | 0 | Contract upgrades, emergency actions, provider management |
| EXECUTOR | 1 | Execute trades, record analytics |
| ARBITRAGE_MANAGER | 2 | Flash loan execution, strategy flows |
| RISK_MANAGER | 3 | Risk scores, circuit breakers |
| CROSSCHAIN_OPERATOR | 4 | Bridge execution only |
| STRATEGY_MANAGER | 5 | Strategy CRUD operations |
| UPDATER | 6 | Parameters, cooldowns, limits |
| VAULT_DEPOSITOR | 7 | Deposit to vault only (AI agent role) |
| GUARDIAN | 8 | Emergency pause only |
| FEE_UPDATER | 9 | Fee rate adjustments only |
| WHITELIST_ADMIN | 10 | Target/selector/DEX whitelists |

### Audit Fixes Implemented

All findings from the Trinity security audit (v1.1) have been addressed:

| Priority | Finding | Fix |
|----------|---------|-----|
| **P0** | AI agent could withdraw from vault | Separated VAULT_DEPOSITOR (deposit-only) from ADMIN (withdraw) |
| **P0** | Missing function bindings | Added 7 critical capability bindings |
| **P1** | UPDATER role too broad | Split into FEE_UPDATER, LIMIT_UPDATER, WHITELIST_ADMIN |
| **P1** | No emergency revocation | Added GUARDIAN role with pause-only capability |

## Project Structure

```
├── src/
│   ├── FeeVault.sol              # ERC4626 vault with fee collection
│   ├── FlashLoanEngine.sol       # Multi-provider flash loan aggregator
│   ├── MEVProtector.sol          # Commit-reveal MEV protection
│   ├── CrossChainRouter.sol      # Timelocked cross-chain configuration
│   ├── RiskEngine.sol            # Token/pair risk scoring
│   ├── QuantumArbitrage.sol      # Core arbitrage logic
│   ├── StrategyOrchestrator.sol  # Strategy management
│   ├── ExecutionTrigger.sol      # Automated execution triggers
│   ├── MaximumSecurityEngine.sol # High-security execution path
│   ├── MinimumCostExecutor.sol   # Gas-optimized execution
│   ├── UltimateArbitrageEngine.sol # Flash loan callback handler
│   ├── StrategyAnalytics.sol     # Performance tracking
│   ├── ExecutionAnalytics.sol    # Execution metrics
│   ├── IntelligenceProcessor.sol # Opportunity queue
│   └── roles/
│       └── Roles.sol             # Role ID constants
├── lib/
│   └── superlib/                 # Superlib library (Solmate-compatible)
│       ├── auth/                 # RolesAuthority, Auth
│       ├── core/                 # ERC20, ERC4626, ERC6909
│       ├── security/             # ReentrancyLib, ECDSA, EIP712
│       ├── transfer/             # SafeTransferLib
│       └── utils/                # MathLib, BytesLib
├── test/
│   ├── RolesAuthority.t.sol      # Unit tests (16 tests)
│   └── RolesInvariant.t.sol      # Invariant fuzz tests (10 tests)
├── script/
│   ├── DeployProduction.s.sol    # Production deployment
│   └── DeployWithRoles.s.sol     # Development deployment
└── deployments/
    ├── DEPLOYMENT_GUIDE.md       # Complete deployment runbook
    └── .env.example              # Environment template
```

## Installation

```bash
# Clone repository
git clone <repo-url>
cd superlib_arbitrage_protocol

# Install dependencies
forge install

# Build
forge build

# Run tests
forge test
```

## Testing

### Unit Tests

```bash
# Run all unit tests
forge test --match-path test/RolesAuthority.t.sol -vvv

# Test specific P0 fixes
forge test --match-test "test_P0" -vvv
```

### Invariant Fuzz Tests

```bash
# Run invariant tests (256 runs, 3840+ calls)
forge test --match-path test/RolesInvariant.t.sol -vvv
```

**Proven invariants:**
- No unauthorized role grants
- No unauthorized vault withdrawals
- No unauthorized pauses
- No unauthorized whitelist modifications
- Owner always retains ADMIN role
- Attacker never gains capabilities
- VAULT_DEPOSITOR cannot withdraw
- Executor cannot manage whitelists
- Fee updater cannot pause

## Deployment

### Prerequisites

1. **Gnosis Safe multisig** (3-of-5 recommended) for ADMIN role
2. **Guardian EOA** for emergency pause capability
3. **AI agent wallet** (optional) for automated execution

### Quick Start

```bash
# Copy environment template
cp deployments/.env.example .env

# Fill in required values
nano .env

# Deploy to mainnet (dry run)
forge script script/DeployProduction.s.sol:DeployProduction \
  --rpc-url $MAINNET_RPC_URL \
  -vvvv

# Deploy to mainnet (live)
forge script script/DeployProduction.s.sol:DeployProduction \
  --rpc-url $MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

See [DEPLOYMENT_GUIDE.md](deployments/DEPLOYMENT_GUIDE.md) for complete instructions.

## AI Agent Integration

The protocol supports autonomous AI agents with constrained permissions:

```solidity
// AI agent receives minimal roles
authority.setUserRole(aiAgent, Roles.EXECUTOR, true);
authority.setUserRole(aiAgent, Roles.CROSSCHAIN_OPERATOR, true);
authority.setUserRole(aiAgent, Roles.VAULT_DEPOSITOR, true);
```

**AI agent CAN:**
- Execute approved arbitrage trades
- Record analytics
- Deposit profits to vault
- Execute cross-chain trades

**AI agent CANNOT:**
- Withdraw from vault
- Modify fee rates
- Pause contracts
- Manage whitelists
- Grant roles to other addresses

## Emergency Procedures

### Guardian Pause

```solidity
// Guardian EOA can pause vault immediately
feeVault.pause();
```

### AI Agent Revocation

```solidity
// From ADMIN multisig
authority.setUserRole(aiAgent, Roles.EXECUTOR, false);
authority.setUserRole(aiAgent, Roles.CROSSCHAIN_OPERATOR, false);
authority.setUserRole(aiAgent, Roles.VAULT_DEPOSITOR, false);
```

## Gas Optimization

The protocol uses Superlib's gas-optimized primitives:

- **SafeTransferLib**: No return value checks for known tokens
- **MathLib**: Unchecked math where overflow is impossible
- **ReentrancyLib**: Transient storage reentrancy guard (EIP-1153)

## License

MIT

## Security

For security concerns, please email security@[domain].com.

**Audit Status:** Trinity methodology audit completed. All P0/P1 findings addressed.

---

Built with [Superlib](https://github.com/superlib/superlib) and [Foundry](https://book.getfoundry.sh/).
