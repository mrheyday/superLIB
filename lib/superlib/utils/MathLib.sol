// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title MathLib
/// @notice Gas-optimized math utilities
library MathLib {
    error MathOverflow();
    error MathDivisionByZero();

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function abs(int256 x) internal pure returns (uint256) {
        return uint256(x >= 0 ? x : -x);
    }

    function clamp(uint256 x, uint256 minVal, uint256 maxVal) internal pure returns (uint256) {
        return x < minVal ? minVal : (x > maxVal ? maxVal : x);
    }

    /// @notice Safe subtraction that returns 0 on underflow
    function safeSub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : 0;
    }

    /// @notice Multiply then divide with full precision intermediate
    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        assembly {
            let prod0 := mul(x, y)
            let mm := mulmod(x, y, not(0))
            let prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            
            if iszero(denominator) {
                mstore(0x00, 0x4e487b71)
                mstore(0x20, 0x12)
                revert(0x1c, 0x24)
            }
            
            if iszero(gt(denominator, prod1)) {
                mstore(0x00, 0x4e487b71)
                mstore(0x20, 0x11)
                revert(0x1c, 0x24)
            }

            result := div(prod0, denominator)
        }
    }

    /// @notice Calculate percentage: (value * bps) / 10000
    function bps(uint256 value, uint256 basisPoints) internal pure returns (uint256) {
        return (value * basisPoints) / 10000;
    }

    /// @notice Square root using Babylonian method
    function sqrt(uint256 x) internal pure returns (uint256 z) {
        assembly {
            z := 181
            let y := x
            if iszero(lt(y, 0x10000000000000000000000000000000000)) {
                y := shr(128, y)
                z := shl(64, z)
            }
            if iszero(lt(y, 0x1000000000000000000)) {
                y := shr(64, y)
                z := shl(32, z)
            }
            if iszero(lt(y, 0x10000000000)) {
                y := shr(32, y)
                z := shl(16, z)
            }
            if iszero(lt(y, 0x1000000)) {
                y := shr(16, y)
                z := shl(8, z)
            }
            z := shr(18, mul(z, add(y, 65536)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := sub(z, lt(div(x, z), z))
        }
    }
}
