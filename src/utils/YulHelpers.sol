// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title YulHelpers
/// @author Superlib Arbitrage Protocol Team
/// @notice Gas-optimized utility functions using Yul (inline assembly)
/// @dev These functions bypass Solidity's safety checks - use only after validation
/// @custom:security Manual audit required - SMTChecker cannot verify assembly
library YulHelpers {
    /*//////////////////////////////////////////////////////////////
                            ROLE OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Check if a role bit is set in the roles bitmask
    /// @param roles The 256-bit roles bitmask
    /// @param role The role ID (0-255) to check
    /// @return has True if role bit is set
    function hasRole(bytes32 roles, uint8 role) internal pure returns (bool has) {
        assembly {
            has := and(shr(role, roles), 1)
        }
    }

    /// @notice Set a role bit in the roles bitmask
    /// @param roles The current roles bitmask
    /// @param role The role ID to enable
    /// @return newRoles Updated bitmask with role enabled
    function setRole(bytes32 roles, uint8 role) internal pure returns (bytes32 newRoles) {
        assembly {
            newRoles := or(roles, shl(role, 1))
        }
    }

    /// @notice Clear a role bit in the roles bitmask
    /// @param roles The current roles bitmask
    /// @param role The role ID to disable
    /// @return newRoles Updated bitmask with role disabled
    function clearRole(bytes32 roles, uint8 role) internal pure returns (bytes32 newRoles) {
        assembly {
            newRoles := and(roles, not(shl(role, 1)))
        }
    }

    /// @notice Check if any role in a capability mask matches user roles
    /// @param userRoles User's role bitmask
    /// @param capability Function's required role bitmask
    /// @return authorized True if user has at least one required role
    function hasAnyRole(bytes32 userRoles, bytes32 capability) internal pure returns (bool authorized) {
        assembly {
            authorized := iszero(iszero(and(userRoles, capability)))
        }
    }

    /*//////////////////////////////////////////////////////////////
                          CALLDATA OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Extract address from calldata at offset
    /// @param offset Byte offset in calldata
    /// @return addr The address at that offset
    function calldataAddress(uint256 offset) internal pure returns (address addr) {
        assembly {
            addr := and(calldataload(offset), 0xffffffffffffffffffffffffffffffffffffffff)
        }
    }

    /// @notice Extract uint256 from calldata at offset
    /// @param offset Byte offset in calldata
    /// @return val The uint256 value
    function calldataUint(uint256 offset) internal pure returns (uint256 val) {
        assembly {
            val := calldataload(offset)
        }
    }

    /*//////////////////////////////////////////////////////////////
                          HASH OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Compute storage slot for mapping(address => bytes32)
    /// @param key The mapping key (address)
    /// @param slot The base storage slot of the mapping
    /// @return storageSlot The computed storage slot
    function mappingSlot(address key, uint256 slot) internal pure returns (bytes32 storageSlot) {
        assembly {
            mstore(0x00, key)
            mstore(0x20, slot)
            storageSlot := keccak256(0x00, 0x40)
        }
    }

    /*//////////////////////////////////////////////////////////////
                            UNCHECKED MATH
    //////////////////////////////////////////////////////////////*/

    /// @notice Unchecked addition (use when overflow impossible)
    /// @param a First operand
    /// @param b Second operand
    /// @return c Sum without overflow check
    function uncheckedAdd(uint256 a, uint256 b) internal pure returns (uint256 c) {
        assembly { c := add(a, b) }
    }

    /// @notice Unchecked subtraction (use when underflow impossible)
    /// @param a First operand
    /// @param b Second operand
    /// @return c Difference without underflow check
    function uncheckedSub(uint256 a, uint256 b) internal pure returns (uint256 c) {
        assembly { c := sub(a, b) }
    }

    /// @notice Division with rounding up
    /// @param a Numerator
    /// @param b Denominator (must be non-zero)
    /// @return c Ceiling of a/b
    function divUp(uint256 a, uint256 b) internal pure returns (uint256 c) {
        assembly { c := div(add(a, sub(b, 1)), b) }
    }

    /// @notice Efficient min function
    /// @param a First value
    /// @param b Second value
    /// @return c Minimum of a and b
    function min(uint256 a, uint256 b) internal pure returns (uint256 c) {
        assembly {
            c := xor(a, mul(xor(a, b), lt(b, a)))
        }
    }

    /// @notice Efficient max function
    /// @param a First value
    /// @param b Second value
    /// @return c Maximum of a and b
    function max(uint256 a, uint256 b) internal pure returns (uint256 c) {
        assembly {
            c := xor(a, mul(xor(a, b), gt(b, a)))
        }
    }
}
