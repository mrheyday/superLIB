// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {BitMath} from "../../src/libraries/math/BitMath.sol";
import {CLZAdapter} from "../../src/libraries/math/CLZAdapter.sol";

/// @dev BitMath/CLZAdapter are `internal`; drive them through an external harness.
contract BitHarness {
    function msb(uint256 x) external pure returns (uint8) {
        return BitMath.mostSignificantBit(x);
    }

    function clz(uint256 x) external pure returns (uint256) {
        return BitMath.leadingZeros(x);
    }

    function ctz(uint256 x) external pure returns (uint256) {
        return BitMath.trailingZeros(x);
    }

    function popCount(uint256 x) external pure returns (uint256) {
        return BitMath.popCount(x);
    }

    function log2(uint256 x) external pure returns (uint256) {
        return CLZAdapter.log2(x);
    }

    function isPow2(uint256 x) external pure returns (bool) {
        return CLZAdapter.isPowerOf2(x);
    }

    function nextPow2(uint256 x) external pure returns (uint256) {
        return CLZAdapter.nextPowerOf2(x);
    }
}

/// @notice Test-drive of the LibBit-backed bit-math (Solady LibBit via BitMath/CLZAdapter,
///         EIP-7939 `clz` on the osaka target).
contract LibBitMathTest is Test {
    BitHarness h;

    function setUp() public {
        h = new BitHarness();
    }

    /* ------------------------------- BitMath -------------------------------- */

    function test_MSB_KnownValues() public view {
        assertEq(h.msb(1), 0);
        assertEq(h.msb(0xFF), 7);
        assertEq(h.msb(0x100), 8);
        assertEq(h.msb(uint256(1) << 255), 255);
    }

    function test_MSB_RevertsOnZero() public {
        vm.expectRevert(BitMath.BitMath__ZeroInput.selector);
        h.msb(0);
    }

    function test_LeadingZeros_KnownValues() public view {
        assertEq(h.clz(1), 255); // one bit at position 0 -> 255 leading zeros
        assertEq(h.clz(uint256(1) << 255), 0);
        assertEq(h.clz(type(uint256).max), 0);
        assertEq(h.clz(0), 256); // clz(0) == bit width
    }

    function test_TrailingZeros_KnownValues() public view {
        assertEq(h.ctz(1), 0);
        assertEq(h.ctz(8), 3); // 0b1000
        assertEq(h.ctz(uint256(1) << 200), 200);
    }

    function test_PopCount_KnownValues() public view {
        assertEq(h.popCount(0), 0);
        assertEq(h.popCount(7), 3); // 0b111
        assertEq(h.popCount(0xFF), 8);
        assertEq(h.popCount(type(uint256).max), 256);
    }

    /// @dev clz + msb are complementary for non-zero inputs: msb == 255 - clz.
    function testFuzz_MSB_ComplementsCLZ(uint256 x) public view {
        vm.assume(x != 0);
        assertEq(uint256(h.msb(x)), 255 - h.clz(x));
    }

    /* ------------------------------ CLZAdapter ------------------------------ */

    function test_Log2_KnownValues() public view {
        assertEq(h.log2(1), 0);
        assertEq(h.log2(2), 1);
        assertEq(h.log2(255), 7);
        assertEq(h.log2(256), 8);
    }

    function test_IsPowerOf2_KnownValues() public view {
        assertTrue(h.isPow2(1));
        assertTrue(h.isPow2(8));
        assertTrue(h.isPow2(uint256(1) << 128));
        assertFalse(h.isPow2(7));
        assertFalse(h.isPow2(0));
    }

    function test_NextPowerOf2_KnownValues() public view {
        assertEq(h.nextPow2(5), 8);
        assertEq(h.nextPow2(8), 8); // already a power of two
        assertEq(h.nextPow2(1), 1);
        assertEq(h.nextPow2(129), 256);
    }
}
