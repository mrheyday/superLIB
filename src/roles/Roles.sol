// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title Roles
/// @author Superlib Arbitrage Protocol Team
/// @notice Single source of truth for all protocol role identifiers
/// @dev Used with Solmate RolesAuthority for capability-based access control.
///      Role IDs are uint8 values (0-255) stored as bits in a bytes32 bitmask.
///      Each role grants specific capabilities across protocol contracts.
/// @custom:security-contact security@example.com
/// @custom:audit-status Trinity Audit v1.1 - All findings addressed
library Roles {
    /// @notice Super-admin role for contract upgrades, emergency actions, and provider management
    /// @dev Assigned to Gnosis Safe multisig (3-of-5 recommended)
    uint8 internal constant ADMIN = 0;

    /// @notice Execution role for trade execution and analytics recording
    /// @dev Assigned to AI agent for automated operations
    uint8 internal constant EXECUTOR = 1;

    /// @notice Flash loan and arbitrage execution role
    /// @dev Can execute flash loans and strategy flows, but cannot withdraw from vault
    uint8 internal constant ARBITRAGE_MANAGER = 2;

    /// @notice Risk management role for scores and circuit breakers
    /// @dev Controls risk parameters across RiskEngine and related contracts
    uint8 internal constant RISK_MANAGER = 3;

    /// @notice Cross-chain bridge execution role
    /// @dev Can execute bridge trades but cannot configure chain parameters
    uint8 internal constant CROSSCHAIN_OPERATOR = 4;

    /// @notice Strategy registration and management role
    /// @dev Can add/remove/toggle strategies in StrategyOrchestrator
    uint8 internal constant STRATEGY_MANAGER = 5;

    /// @notice Parameter update role for cooldowns, limits, and general settings
    /// @dev Split from original broad UPDATER for granular control (P1 fix)
    uint8 internal constant UPDATER = 6;

    /// @notice Vault deposit-only role (P0 audit fix)
    /// @dev Can deposit to FeeVault but CANNOT withdraw or redeem
    /// @custom:audit P0 fix - Separated from withdrawal capability
    uint8 internal constant VAULT_DEPOSITOR = 7;

    /// @notice Emergency pause role (P1 audit fix)
    /// @dev Can pause FeeVault in emergencies, assigned to fast-response EOA
    /// @custom:audit P1 fix - Added for emergency response
    uint8 internal constant GUARDIAN = 8;

    /// @notice Fee rate adjustment role (P1 audit fix)
    /// @dev Can modify deposit/withdraw/performance fees only
    /// @custom:audit P1 fix - Split from UPDATER for granular control
    uint8 internal constant FEE_UPDATER = 9;

    /// @notice Whitelist management role (P0 audit fix)
    /// @dev Controls target/selector/DEX whitelists - elevated permission
    /// @custom:audit P0 fix - Elevated from UPDATER due to attack surface
    uint8 internal constant WHITELIST_ADMIN = 10;
}
