// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {MEVReserveMath} from "../../src/libraries/mev/MEVReserveMath.sol";

/// @notice Test-drive of MEVReserveMath, extracted from the deleted MegaMEVOptimizationLib
///         (which was ~90% unused Solady FixedPointMathLib/LibBit duplication). Pins down
///         the same behavior the 4 surviving MEV-specific functions had before extraction.
contract MEVReserveMathTest is Test {
    function test_MagnitudeBucket_ZeroReturnsZero() public pure {
        assertEq(MEVReserveMath.magnitudeBucket(0), 0);
    }

    function test_MagnitudeBucket_KnownValues() public pure {
        assertEq(MEVReserveMath.magnitudeBucket(1), 0);
        assertEq(MEVReserveMath.magnitudeBucket(0xFF), 7);
        assertEq(MEVReserveMath.magnitudeBucket(1 << 20), 20);
    }

    function test_ReserveImbalanceBucket_ZeroReserveIsMaxImbalance() public pure {
        assertEq(MEVReserveMath.reserveImbalanceBucket(0, 100), type(uint256).max);
        assertEq(MEVReserveMath.reserveImbalanceBucket(100, 0), type(uint256).max);
    }

    function test_ReserveImbalanceBucket_EqualReservesAreBalanced() public pure {
        assertEq(MEVReserveMath.reserveImbalanceBucket(1000, 1000), 0);
    }

    function test_ReserveImbalanceBucket_Symmetric() public pure {
        assertEq(
            MEVReserveMath.reserveImbalanceBucket(1 << 4, 1 << 20),
            MEVReserveMath.reserveImbalanceBucket(1 << 20, 1 << 4)
        );
        assertEq(MEVReserveMath.reserveImbalanceBucket(1 << 4, 1 << 20), 16);
    }

    function test_RejectByReserveShape_RejectsThinReserve() public pure {
        // reserveB has bitLength 1 (< minBitLength 8) -> reject
        assertTrue(MEVReserveMath.rejectByReserveShape(1 << 30, 1, 8, 100));
    }

    function test_RejectByReserveShape_RejectsExtremeImbalance() public pure {
        // both pass the bit-length floor, but the magnitude gap exceeds maxImbalanceBucket
        assertTrue(MEVReserveMath.rejectByReserveShape(1 << 200, 1 << 10, 8, 5));
    }

    function test_RejectByReserveShape_AcceptsHealthyPool() public pure {
        assertFalse(MEVReserveMath.rejectByReserveShape(1 << 40, 1 << 42, 8, 10));
    }

    function test_LiquidityClass_UsesSmallerReserve() public pure {
        // liquidityClass == bitLength(min(reserveA, reserveB))
        assertEq(MEVReserveMath.liquidityClass(1 << 50, 1 << 10), 11); // bitLength(2^10) = 11
        assertEq(MEVReserveMath.liquidityClass(1 << 10, 1 << 50), 11); // order-independent
    }

    function test_LiquidityClass_ZeroReserveIsZeroClass() public pure {
        assertEq(MEVReserveMath.liquidityClass(0, 1 << 50), 0);
    }
}
