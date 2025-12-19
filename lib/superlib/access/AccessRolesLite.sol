// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title AccessRolesLite
/// @notice Minimal inline role-checking for contracts using RolesAuthority
/// @dev Provides helper modifiers and checks without additional storage
abstract contract AccessRolesLite {
    error AccessDenied();
    error InvalidRole();

    /// @notice Check if caller has specific role via authority
    /// @dev Override in implementing contract to wire to actual authority
    function _hasRole(uint8 role, address account) internal view virtual returns (bool);

    modifier onlyRole(uint8 role) {
        if (!_hasRole(role, msg.sender)) revert AccessDenied();
        _;
    }

    modifier onlyRoles(uint8 role1, uint8 role2) {
        if (!_hasRole(role1, msg.sender) && !_hasRole(role2, msg.sender)) revert AccessDenied();
        _;
    }
}
