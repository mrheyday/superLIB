// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";
import { BitMath } from "../math/BitMath.sol";

/// @title MEVReserveMath
/// @notice Reserve-shape heuristics for pre-filtering candidate AMM pools before
///         expensive simulation: magnitude bucketing, imbalance scoring, and a
///         cheap admission gate. Not a price model.
/// @dev Extracted from the former MegaMEVOptimizationLib, which folded in ~50
///      generic Solady FixedPointMathLib/LibBit functions that duplicated
///      already-vendored code with no unique value. This library keeps only
///      the genuinely MEV-specific pieces and imports Solady/BitMath directly.
library MEVReserveMath {
    /// @notice Compact magnitude bucket for reserves/liquidity.
    /// @dev Returns floor(log2(x)); returns 0 for x == 0.
    function magnitudeBucket(
        uint256 x
    ) internal pure returns (uint256) {
        return x == 0 ? 0 : BitMath.mostSignificantBit(x);
    }

    /// @notice Fast reserve imbalance score.
    /// @dev Higher means more imbalance. Uses log2 distance, not price-accurate math.
    function reserveImbalanceBucket(
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256) {
        if (reserveA == 0 || reserveB == 0) return type(uint256).max;

        uint256 a = magnitudeBucket(reserveA);
        uint256 b = magnitudeBucket(reserveB);
        return a > b ? a - b : b - a;
    }

    /// @notice Returns true if reserves are too small or too imbalanced for expensive simulation.
    function rejectByReserveShape(
        uint256 reserveA,
        uint256 reserveB,
        uint256 minBitLength,
        uint256 maxImbalanceBucket
    ) internal pure returns (bool) {
        if (_bitLength(reserveA) < minBitLength) return true;
        if (_bitLength(reserveB) < minBitLength) return true;
        return reserveImbalanceBucket(reserveA, reserveB) > maxImbalanceBucket;
    }

    /// @notice Fast approximate liquidity class for ranking candidate pools.
    /// @dev Not a price model. Use only for pre-filtering.
    function liquidityClass(
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256) {
        uint256 minReserve = FixedPointMathLib.min(reserveA, reserveB);
        return _bitLength(minReserve);
    }

    /// @dev Number of bits needed to represent x. `_bitLength(0) == 0`.
    function _bitLength(
        uint256 x
    ) private pure returns (uint256) {
        return x == 0 ? 0 : BitMath.mostSignificantBit(x) + 1;
    }
}
