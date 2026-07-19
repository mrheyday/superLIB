// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import { MEVReserveMath } from "./MEVReserveMath.sol";

/// @title  ReserveShapeAdmission
/// @author mev-arbitrum
/// @notice Composes the MEVReserveMath reserve-shape heuristics into a
///         single admission gate for candidate AMM pools.
/// @dev    A cheap CLZ-backed pre-filter — NOT a price model. It screens out
///         pools that are not worth quoting or attacking: dust reserves (too
///         few significant bits), lopsided reserves (large log2 magnitude gap),
///         and shallow liquidity. Reusable by any path that holds raw reserves
///         (PathFinder route quoting, FrontrunCalldata sandwich sizing, …).
///         Reserve magnitudes are compared via integer `log2` distance, so the
///         thresholds are bit-scale, not token-decimal-scale.
library ReserveShapeAdmission {
    /// @notice Admission thresholds.
    /// @param minReserveBitLength Each reserve must have at least this many
    ///        significant bits (`bitLength`); screens out dust pools.
    /// @param maxImbalanceBucket  Max allowed |log2(reserveA) - log2(reserveB)|;
    ///        screens out lopsided pools where the price math is fragile.
    /// @param minLiquidityClass   The smaller reserve must have at least this
    ///        many significant bits; a depth floor for the shallow side.
    struct Thresholds {
        uint16 minReserveBitLength;
        uint16 maxImbalanceBucket;
        uint16 minLiquidityClass;
    }

    /// @notice Default admission thresholds shared by all consumers (PathFinder
    ///         route discovery, FrontrunCalldata sandwich sizing). Single source
    ///         of truth for the default policy.
    /// @dev    Bit-scale gates: screen out dust (< ~2^16 reserves), lopsided
    ///         pools (>2^40 log2 magnitude gap), and shallow liquidity. The
    ///         imbalance bucket is decimal-sensitive (raw log2 magnitude, not
    ///         price-normalized), so a 6-vs-18-decimal pool such as USDC/WETH
    ///         sits ~28 buckets apart and stays admitted under the 40 ceiling.
    ///         Use the `Thresholds` overload for path-specific tuning.
    uint16 internal constant DEFAULT_MIN_RESERVE_BITLENGTH = 16;
    uint16 internal constant DEFAULT_MAX_IMBALANCE_BUCKET = 40;
    uint16 internal constant DEFAULT_MIN_LIQUIDITY_CLASS = 16;

    /// @notice Admission using the shared DEFAULT_* thresholds.
    /// @param reserveA First reserve (raw, token-native units).
    /// @param reserveB Second reserve (raw, token-native units).
    /// @return ok      True if the pool is admitted under the default policy.
    function admit(
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (bool ok) {
        return admit(
            reserveA,
            reserveB,
            Thresholds({
                minReserveBitLength: DEFAULT_MIN_RESERVE_BITLENGTH,
                maxImbalanceBucket: DEFAULT_MAX_IMBALANCE_BUCKET,
                minLiquidityClass: DEFAULT_MIN_LIQUIDITY_CLASS
            })
        );
    }

    /// @notice Returns true if the pool passes every admission gate.
    /// @param reserveA First reserve (raw, token-native units).
    /// @param reserveB Second reserve (raw, token-native units).
    /// @param t        Admission thresholds.
    /// @return ok      True if the pool is admitted for further processing.
    function admit(
        uint256 reserveA,
        uint256 reserveB,
        Thresholds memory t
    ) internal pure returns (bool ok) {
        if (reserveA == 0 || reserveB == 0) return false;
        // `rejectByReserveShape` folds in the per-reserve bit-length floor and
        // the imbalance ceiling.
        if (MEVReserveMath.rejectByReserveShape(
                reserveA, reserveB, t.minReserveBitLength, t.maxImbalanceBucket
            )) {
            return false;
        }
        // Additional depth floor on the shallow side.
        if (MEVReserveMath.liquidityClass(reserveA, reserveB) < t.minLiquidityClass) {
            return false;
        }
        return true;
    }

    /// @notice Non-gating classification tuple for scoring / telemetry.
    /// @param reserveA First reserve.
    /// @param reserveB Second reserve.
    /// @return imbalanceBucket |log2(reserveA) - log2(reserveB)|.
    /// @return liquidityClass  Significant-bit depth of the smaller reserve.
    /// @return magnitudeA      `log2Floor(reserveA)`.
    /// @return magnitudeB      `log2Floor(reserveB)`.
    function classify(
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256 imbalanceBucket, uint256 liquidityClass, uint256 magnitudeA, uint256 magnitudeB) {
        imbalanceBucket = MEVReserveMath.reserveImbalanceBucket(reserveA, reserveB);
        liquidityClass = MEVReserveMath.liquidityClass(reserveA, reserveB);
        magnitudeA = MEVReserveMath.magnitudeBucket(reserveA);
        magnitudeB = MEVReserveMath.magnitudeBucket(reserveB);
    }
}
