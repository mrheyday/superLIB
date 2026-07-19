// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {BitMath} from "../../src/libraries/math/BitMath.sol";

/// @dev BitMath is `internal`; drive it through an external harness.
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

    function nextPow2(uint256 x) external pure returns (uint256) {
        return BitMath.nextPowerOf2(x);
    }

    function topNBits(uint256 bitmap, uint256 n) external pure returns (uint256[] memory) {
        return BitMath.findTopNBits(bitmap, n);
    }
}

/// @notice Test-drive of the LibBit-backed bit-math (Solady LibBit via BitMath,
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

    function test_NextPowerOf2_KnownValues() public view {
        assertEq(h.nextPow2(5), 8);
        assertEq(h.nextPow2(8), 8); // already a power of two
        assertEq(h.nextPow2(1), 1);
        assertEq(h.nextPow2(129), 256);
        assertEq(h.nextPow2(0), 1);
    }

    /// @dev x == 2**255 is already a power of two -> returns itself, no overflow.
    function test_NextPowerOf2_BoundaryPowerOfTwoDoesNotRevert() public view {
        assertEq(h.nextPow2(uint256(1) << 255), uint256(1) << 255);
    }

    /// @dev x > 2**255 and not itself a power of two -> true result (2**256)
    ///      doesn't fit in a uint256; must revert rather than silently wrap to 0.
    function test_NextPowerOf2_RevertsOnOverflow() public {
        vm.expectRevert(BitMath.BitMath__NextPowerOf2Overflow.selector);
        h.nextPow2((uint256(1) << 255) + 1);
    }

    function test_NextPowerOf2_RevertsOnOverflow_MaxUint() public {
        vm.expectRevert(BitMath.BitMath__NextPowerOf2Overflow.selector);
        h.nextPow2(type(uint256).max);
    }

    function test_FindTopNBits_HighestFirst() public view {
        // 0b1011 = bits {0, 1, 3} set; top 2 highest-first -> [3, 1]
        uint256[] memory top = h.topNBits(0xB, 2);
        assertEq(top.length, 2);
        assertEq(top[0], 3);
        assertEq(top[1], 1);
    }

    function test_FindTopNBits_ShrinksWhenFewerSetBits() public view {
        // only 1 bit set, but 3 requested -> array shrinks to length 1
        uint256[] memory top = h.topNBits(0x10, 3);
        assertEq(top.length, 1);
        assertEq(top[0], 4);
    }
}
