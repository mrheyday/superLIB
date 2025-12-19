# Architecture Documentation

This document provides an in-depth explanation of the protocol architecture, contract relationships, and design decisions.

## System Overview

The DeFi Arbitrage Protocol is designed as a modular system where each contract has a specific responsibility. Contracts communicate through well-defined interfaces with security checks at every boundary. The architecture prioritizes security over gas efficiency, recognizing that in arbitrage the profit margins typically justify additional validation costs.

## Contract Layers

### Layer 1: Vault and Asset Management

The FeeVault serves as the treasury for protocol fees and rewards. It implements the ERC4626 tokenized vault standard, providing a familiar interface for deposits and withdrawals. Depositors receive shares proportional to their contribution and can claim rewards from the reward pool.

The vault incorporates inflation attack protection through a dead shares mechanism. During construction, 1000 shares are minted to a burn address. This ensures the share price cannot be manipulated by donation attacks against first depositors, as there are always shares outstanding that set a baseline price.

Fee collection flows through the vault from all revenue-generating operations. The FlashLoanEngine, UltimateArbitrageEngine, and CrossChainRouter all direct a percentage of profits to the vault, which accumulates until distributed to stakers.

### Layer 2: Risk and Strategy Management

The RiskEngine calculates risk scores for operations based on token risk profiles, execution conditions, and historical data. Each token can have an individual risk score assigned, and compound scores are calculated for multi-token operations. Score bounds are enforced to prevent overflow and underflow conditions.

The StrategyOrchestrator manages the portfolio of active arbitrage strategies. Each strategy has parameters including type, capital allocation, risk tolerance, profit targets, and stop-loss thresholds. The orchestrator enforces a maximum of 100 active strategies to prevent unbounded array growth. Pagination is provided for strategy enumeration.

The StrategyAnalytics contract tracks execution metrics for each strategy including trade count, profit, loss, and execution timestamps. This data informs the orchestrator's prioritization decisions and provides transparency into strategy performance.

### Layer 3: Security Layer

The MEVProtector implements front-running protection through a commit-reveal scheme. Users first commit to their execution parameters by submitting a hash of the target, calldata, and a salt value. After waiting a minimum number of blocks, they can execute by revealing the original parameters. The contract validates that the revealed parameters match the commitment and that the timing constraints are satisfied.

Target whitelisting ensures only approved contracts can be called through the protector. Function selector whitelisting provides an additional layer by restricting which functions can be invoked even on approved targets. This dual whitelisting prevents arbitrary code execution even if an attacker controls a whitelisted contract.

The MaximumSecurityEngine provides rate-limited execution with comprehensive security validation. It enforces a maximum of 10 calls per 60-second period per user, preventing resource exhaustion attacks. Security scores are calculated for each execution request, and requests below the minimum threshold are rejected.

### Layer 4: Execution Engines

The FlashLoanEngine manages integration with flash loan providers such as Aave and Compound. Provider configurations include the provider address and fee percentage. The engine validates that provider fees do not exceed the maximum cap of 500 basis points.

DEX router whitelisting restricts which decentralized exchanges can be used in arbitrage paths. This prevents attackers from routing trades through malicious contracts that could manipulate prices or steal funds.

The UltimateArbitrageEngine executes zero-capital arbitrage using flash loans. It captures balance snapshots before and after execution to verify that claimed profits are real. Flash loan pools must be whitelisted before they can be used, preventing callback exploitation from malicious pools.

The QuantumArbitrage contract orchestrates the flash loan engine and risk engine with timelocked updates. Changes to the underlying engines require a 24-hour waiting period, providing time to detect and respond to malicious updates.

### Layer 5: Cross-Chain Operations

The CrossChainRouter manages trades across multiple blockchain networks. Each supported chain has a configuration specifying the bridge address, minimum and maximum trade amounts, and active status.

Configuration changes are protected by a 24-hour timelock. When a new configuration is queued, it cannot be applied until the timelock expires. This prevents instant reconfiguration that could redirect funds to malicious bridges.

Daily volume limits are enforced per chain to contain exposure from any single chain's compromise. The limits reset each day and are tracked independently for each destination chain.

## Data Flow

### Arbitrage Execution Flow

An arbitrage execution begins when a keeper identifies a profitable opportunity and submits it through the MEVProtector. The keeper first commits to the execution parameters by calling `commitExecution` with a hash of the target, calldata, and salt. After waiting the required blocks, the keeper calls `executeProtectedArbitrage` with the revealed parameters.

The MEVProtector validates the commitment, then forwards the call to the target contract. If the target is the UltimateArbitrageEngine, it captures a balance snapshot, executes the flash loan and arbitrage path through whitelisted providers and DEXes, captures the post-execution balance, and verifies the profit claim.

Fees are extracted from the profit and sent to the FeeVault. The remaining profit is returned to the keeper. The execution is logged for analytics tracking.

### Cross-Chain Trade Flow

Cross-chain trades route through the CrossChainRouter. The router validates that the destination chain is active, the amount is within configured bounds, and the daily volume limit has not been exceeded.

The router then interacts with the configured bridge for that chain, passing the trade parameters and any required bridge-specific data. The bridge returns a message ID that can be used to track the cross-chain transaction.

## Access Control Model

The protocol uses a role-based access control model with the following roles.

The Owner role has ultimate authority over contract configuration including whitelist management, fee parameters, and engine updates. This role should be assigned to a multisig wallet in production.

The Authorized Executor role can execute protected arbitrage operations. This role is typically assigned to keeper bots that monitor for opportunities.

The Fee Manager role can update fee parameters within defined bounds. This role allows operational adjustments without requiring owner intervention.

The Rewards Manager role can add rewards to the vault reserve. This role is assigned to contracts or addresses that fund the reward pool.

## Upgrade Considerations

The contracts are intentionally non-upgradeable to reduce the attack surface. Upgradeable contracts introduce risks including storage layout collisions, implementation bugs affecting proxies, and centralization through upgrade authority.

To deploy updated contract versions, the protocol uses a migration pattern. New contracts are deployed, engine addresses in dependent contracts are updated through the timelock mechanism, authorization is transferred to the new contracts, and the old contracts are deprecated by removing their authorizations.

This approach preserves the security benefits of immutable contracts while allowing the protocol to evolve. The 24-hour timelock on engine updates provides transparency and reaction time for the community.

## Gas Optimization

While security takes priority, several gas optimizations are implemented. Storage variables are packed where possible to reduce slot usage. Short-circuit evaluation is used in validation checks to avoid unnecessary computation. Events use indexed parameters for efficient filtering. View functions use memory efficiently to reduce read costs.

Pagination in array-heavy functions prevents gas exhaustion on iteration. The `getStrategiesPaginated` function accepts offset and limit parameters, allowing clients to fetch strategies in manageable batches rather than loading all at once.

## Monitoring and Observability

All state changes emit events to enable off-chain monitoring. Critical events that should trigger alerts include `ThreatDetected` indicating a potential attack, `ChainConfigQueued` indicating a pending cross-chain configuration change, `EngineUpdateQueued` indicating a pending engine migration, and any event on contracts from unexpected addresses.

The StrategyAnalytics contract provides on-chain metrics that can be queried to assess protocol health. Off-chain indexers can aggregate event data to build dashboards showing execution volume, profit distribution, and security incidents.
