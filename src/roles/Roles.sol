// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Roles
/// @notice Single source of truth for all protocol roles
/// @dev Used with Solmate RolesAuthority for capability-based access control
library Roles {
    uint8 internal constant ADMIN               = 0;
    uint8 internal constant EXECUTOR            = 1;
    uint8 internal constant ARBITRAGE_MANAGER   = 2;
    uint8 internal constant RISK_MANAGER        = 3;
    uint8 internal constant CROSSCHAIN_OPERATOR = 4;
    uint8 internal constant STRATEGY_MANAGER    = 5;
    uint8 internal constant UPDATER             = 6;
    uint8 internal constant VAULT_DEPOSITOR     = 7;  // P0 fix: separate from withdrawal
    uint8 internal constant GUARDIAN            = 8;  // P1 fix: emergency revocation
    uint8 internal constant FEE_UPDATER         = 9;  // P1 fix: granular updates
    uint8 internal constant WHITELIST_ADMIN     = 10; // P1 fix: attack surface control
}
