# Roles
[Git Source](https://github.com/example/superlib-arbitrage-protocol/blob/95c67768e2bfb00fae071b9d9bbef75272ead523/src/roles/Roles.sol)

**Title:**
Roles

**Author:**
Superlib Arbitrage Protocol Team

Single source of truth for all protocol role identifiers

Used with Solmate RolesAuthority for capability-based access control.
Role IDs are uint8 values (0-255) stored as bits in a bytes32 bitmask.
Each role grants specific capabilities across protocol contracts.

**Notes:**
- security-contact: security@example.com

- audit-status: Trinity Audit v1.1 - All findings addressed


## State Variables
### ADMIN
Super-admin role for contract upgrades, emergency actions, and provider management

Assigned to Gnosis Safe multisig (3-of-5 recommended)


```solidity
uint8 internal constant ADMIN = 0
```


### EXECUTOR
Execution role for trade execution and analytics recording

Assigned to AI agent for automated operations


```solidity
uint8 internal constant EXECUTOR = 1
```


### ARBITRAGE_MANAGER
Flash loan and arbitrage execution role

Can execute flash loans and strategy flows, but cannot withdraw from vault


```solidity
uint8 internal constant ARBITRAGE_MANAGER = 2
```


### RISK_MANAGER
Risk management role for scores and circuit breakers

Controls risk parameters across RiskEngine and related contracts


```solidity
uint8 internal constant RISK_MANAGER = 3
```


### CROSSCHAIN_OPERATOR
Cross-chain bridge execution role

Can execute bridge trades but cannot configure chain parameters


```solidity
uint8 internal constant CROSSCHAIN_OPERATOR = 4
```


### STRATEGY_MANAGER
Strategy registration and management role

Can add/remove/toggle strategies in StrategyOrchestrator


```solidity
uint8 internal constant STRATEGY_MANAGER = 5
```


### UPDATER
Parameter update role for cooldowns, limits, and general settings

Split from original broad UPDATER for granular control (P1 fix)


```solidity
uint8 internal constant UPDATER = 6
```


### VAULT_DEPOSITOR
Vault deposit-only role (P0 audit fix)

Can deposit to FeeVault but CANNOT withdraw or redeem

**Note:**
audit: P0 fix - Separated from withdrawal capability


```solidity
uint8 internal constant VAULT_DEPOSITOR = 7
```


### GUARDIAN
Emergency pause role (P1 audit fix)

Can pause FeeVault in emergencies, assigned to fast-response EOA

**Note:**
audit: P1 fix - Added for emergency response


```solidity
uint8 internal constant GUARDIAN = 8
```


### FEE_UPDATER
Fee rate adjustment role (P1 audit fix)

Can modify deposit/withdraw/performance fees only

**Note:**
audit: P1 fix - Split from UPDATER for granular control


```solidity
uint8 internal constant FEE_UPDATER = 9
```


### WHITELIST_ADMIN
Whitelist management role (P0 audit fix)

Controls target/selector/DEX whitelists - elevated permission

**Note:**
audit: P0 fix - Elevated from UPDATER due to attack surface


```solidity
uint8 internal constant WHITELIST_ADMIN = 10
```


