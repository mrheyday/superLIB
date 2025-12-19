// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Auth, Authority} from "./Auth.sol";

/// @title RolesAuthority
/// @notice Role-based capability authorization system
/// @dev Based on Solmate's RolesAuthority with optimizations
contract RolesAuthority is Auth, Authority {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event UserRoleUpdated(address indexed user, uint8 indexed role, bool enabled);
    event PublicCapabilityUpdated(address indexed target, bytes4 indexed functionSig, bool enabled);
    event RoleCapabilityUpdated(uint8 indexed role, address indexed target, bytes4 indexed functionSig, bool enabled);

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Tracks which roles each user has
    mapping(address => bytes32) public getUserRoles;

    /// @notice Tracks which capabilities are public (callable by anyone)
    mapping(address => mapping(bytes4 => bool)) public isCapabilityPublic;

    /// @notice Tracks which roles can call which functions on which targets
    mapping(address => mapping(bytes4 => bytes32)) public getRolesWithCapability;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, Authority _authority) Auth(_owner, _authority) {}

    /*//////////////////////////////////////////////////////////////
                           AUTHORIZATION LOGIC
    //////////////////////////////////////////////////////////////*/

    function canCall(address user, address target, bytes4 functionSig) public view virtual override returns (bool) {
        return isCapabilityPublic[target][functionSig] 
            || bytes32(0) != getUserRoles[user] & getRolesWithCapability[target][functionSig];
    }

    function doesUserHaveRole(address user, uint8 role) public view virtual returns (bool) {
        return (uint256(getUserRoles[user]) >> role) & 1 != 0;
    }

    function doesRoleHaveCapability(uint8 role, address target, bytes4 functionSig) public view virtual returns (bool) {
        return (uint256(getRolesWithCapability[target][functionSig]) >> role) & 1 != 0;
    }

    /*//////////////////////////////////////////////////////////////
                              ROLE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function setPublicCapability(address target, bytes4 functionSig, bool enabled) public virtual requiresAuth {
        isCapabilityPublic[target][functionSig] = enabled;
        emit PublicCapabilityUpdated(target, functionSig, enabled);
    }

    function setRoleCapability(uint8 role, address target, bytes4 functionSig, bool enabled) public virtual requiresAuth {
        if (enabled) {
            getRolesWithCapability[target][functionSig] |= bytes32(1 << role);
        } else {
            getRolesWithCapability[target][functionSig] &= ~bytes32(1 << role);
        }
        emit RoleCapabilityUpdated(role, target, functionSig, enabled);
    }

    function setUserRole(address user, uint8 role, bool enabled) public virtual requiresAuth {
        if (enabled) {
            getUserRoles[user] |= bytes32(1 << role);
        } else {
            getUserRoles[user] &= ~bytes32(1 << role);
        }
        emit UserRoleUpdated(user, role, enabled);
    }
}
