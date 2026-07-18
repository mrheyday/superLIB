// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import { LibBit } from "solady/utils/LibBit.sol";

/// @title CLZAdapter
/// @notice CLZ (Count Leading Zeros) adapter using native Osaka EVM opcode
/// @dev Uses Solady's CLZ branch with native CLZ opcode support
/// @custom:security Requires Osaka EVM (evm_version = "osaka")
library CLZAdapter {
    using LibBit for uint256;

    // ============== Constants ==============

    /// @dev Native CLZ gas cost (per EIP-7939)
    uint256 constant CLZ_GAS_COST = 5;

    // ============== CLZ Functions ==============

    /// @notice Count leading zeros using native CLZ opcode
    /// @param x Value to count leading zeros for
    /// @return r Number of leading zeros (0-256)
    function clz(uint256 x) internal pure returns (uint256 r) {
        assembly ("memory-safe") {
            r := clz(x)
        }
    }

    // ============== Helper Functions ==============

    /// @notice Check if Osaka EVM is active (CLZ available)
    /// @return True - always true for Osaka EVM builds
    function isFusakaActive() internal pure returns (bool) {
        return true; // Osaka EVM always has CLZ
    }

    /// @notice Find highest set bit using CLZ
    /// @param x Value to find highest bit for
    /// @return bit Index of highest set bit (0-255), or max uint256 if x=0
    function findHighestBit(uint256 x) internal pure returns (uint256 bit) {
        if (x == 0) return type(uint256).max;
        assembly ("memory-safe") {
            bit := sub(255, clz(x))
        }
    }

    /// @notice Find lowest set bit using CLZ
    /// @param x Value to find lowest bit for
    /// @return bit Index of lowest set bit (0-255), or max uint256 if x=0
    function findLowestBit(uint256 x) internal pure returns (uint256 bit) {
        if (x == 0) return type(uint256).max;
        // Isolate rightmost set bit: x & -x
        uint256 isolated;
        assembly ("memory-safe") {
            isolated := and(x, sub(0, x))
            bit := sub(255, clz(isolated))
        }
    }

    /// @notice Calculate log2 using CLZ
    /// @param x Value to calculate log2 for (must be > 0)
    /// @return result Floor of log2(x)
    function log2(uint256 x) internal pure returns (uint256 result) {
        require(x > 0, "log2(0) undefined");
        assembly ("memory-safe") {
            result := sub(255, clz(x))
        }
    }

    /// @notice Count number of set bits (popcount)
    /// @param x Value to count set bits for
    /// @return count Number of set bits
    function popcount(uint256 x) internal pure returns (uint256 count) {
        return LibBit.popCount(x);
    }

    /// @notice Check if value is power of 2
    /// @param x Value to check
    /// @return True if x is a power of 2
    function isPowerOf2(uint256 x) internal pure returns (bool) {
        return LibBit.isPo2(x);
    }

    /// @notice Round up to next power of 2
    /// @dev Uses CLZ to find required bit width
    /// @param x Value to round up
    /// @return next Next power of 2 >= x
    function nextPowerOf2(uint256 x) internal pure returns (uint256 next) {
        if (x == 0) return 1;
        if (isPowerOf2(x)) return x;

        // Find highest bit and add 1
        uint256 highestBit = findHighestBit(x);
        return uint256(1) << (highestBit + 1);
    }

    // ============== Batch Operations ==============

    /// @notice Find multiple highest bits in a bitmap
    /// @dev Efficiently extract top N set bits using CLZ
    /// @param bitmap Bitmap to scan
    /// @param n Number of bits to find
    /// @return bits Array of bit indices (highest to lowest)
    function findTopNBits(uint256 bitmap, uint256 n) internal pure returns (uint256[] memory bits) {
        bits = new uint256[](n);
        uint256 remaining = bitmap;
        uint256 count = 0;

        while (count < n && remaining != 0) {
            uint256 highestBit = findHighestBit(remaining);
            bits[count] = highestBit;

            // Clear this bit
            remaining &= ~(uint256(1) << highestBit);
            count++;
        }

        // Resize array if we found fewer than n bits
        if (count < n) {
            assembly ("memory-safe") {
                mstore(bits, count)
            }
        }
    }

    /// @notice Calculate bit width of a number
    /// @param x Value to calculate bit width for
    /// @return width Bit width (1-256, or 0 for x=0)
    function bitWidth(uint256 x) internal pure returns (uint256 width) {
        if (x == 0) return 0;
        assembly ("memory-safe") {
            width := sub(256, clz(x))
        }
    }

    // ============== Gas Info ==============

    /// @notice Estimate gas savings from native CLZ vs library
    /// @return saved Approximate gas saved per CLZ call
    function estimateGasSavings() internal pure returns (uint256 saved) {
        // Library: ~180 gas, Native: 5 gas (EIP-7939)
        return 175;
    }

    /// @notice Get CLZ implementation info
    /// @return isNative True (always native on Osaka)
    /// @return gasCost Approximate gas cost per call
    function getImplementationInfo() internal pure returns (bool isNative, uint256 gasCost) {
        return (true, CLZ_GAS_COST);
    }
}
