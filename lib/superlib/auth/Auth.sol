// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Authority
/// @notice Interface for authorization logic
interface Authority {
    function canCall(address user, address target, bytes4 functionSig) external view returns (bool);
}

/// @title Auth
/// @notice Provides flexible authorization via pluggable Authority
/// @dev Based on Solmate's Auth pattern
abstract contract Auth {
    event OwnershipTransferred(address indexed user, address indexed newOwner);
    event AuthorityUpdated(address indexed user, Authority indexed newAuthority);

    address public owner;
    Authority public authority;

    error Unauthorized();

    constructor(address _owner, Authority _authority) {
        owner = _owner;
        authority = _authority;
        emit OwnershipTransferred(address(0), _owner);
        emit AuthorityUpdated(address(0), _authority);
    }

    modifier requiresAuth() virtual {
        if (!isAuthorized(msg.sender, msg.sig)) revert Unauthorized();
        _;
    }

    function isAuthorized(address user, bytes4 functionSig) internal view virtual returns (bool) {
        Authority auth = authority;
        return (address(auth) != address(0) && auth.canCall(user, address(this), functionSig)) || user == owner;
    }

    function setAuthority(Authority newAuthority) public virtual {
        if (msg.sender != owner) revert Unauthorized();
        authority = newAuthority;
        emit AuthorityUpdated(msg.sender, newAuthority);
    }

    function transferOwnership(address newOwner) public virtual {
        if (msg.sender != owner) revert Unauthorized();
        owner = newOwner;
        emit OwnershipTransferred(msg.sender, newOwner);
    }
}
