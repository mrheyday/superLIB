// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title MegaMEVOptimizationLib
/// @notice CLZ-backed bit math, full-precision arithmetic, and lightweight MEV route heuristics.
/// @dev Single-library build with no external imports: the Solady `FixedPointMathLib` and `LibBit`
///      primitives this library depends on are folded in. Public CLZ-backed helpers are backed by
///      the native EIP-7939 `clz` opcode (osaka target). Uses deterministic CLZ semantics
///      compatible across supported toolchains. Math primitives derived from Solady (MIT,
///      https://github.com/vectorized/solady).
library MegaMEVOptimizationLib {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    uint256 internal constant WAD_UINT = 1e18;
    uint256 internal constant Q96 = 0x1000000000000000000000000;
    uint256 internal constant Q128 = 0x100000000000000000000000000000000;
    uint256 internal constant INT256_MIN_ABS = 1 << 255;
    int256 internal constant WAD_INT = 1e18;

    /// @dev The scalar of ETH and most ERC20s (folded from Solady FixedPointMathLib).
    uint256 private constant WAD = 1e18;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error DivisionByZero();
    error InvalidBounds();
    error ZeroInput();
    error PowerOfTwoOverflow();
    error SignedMathOverflow();

    /// @dev The full precision multiply-divide operation failed, either due
    /// to the result being larger than 256 bits, or a division by a zero.
    error FullMulDivFailed();

    /// @dev The division failed, as the denominator is zero.
    error DivFailed();

    /// @dev The operation failed, due to an overflow.
    error RPowOverflow();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       PUBLIC SURFACE                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Absolute value of a signed integer as uint256.
    /// @dev Safe for `type(int256).min`. Folded from Solady FixedPointMathLib (abs).
    function abs(
        int256 x
    ) internal pure returns (uint256 z) {
        unchecked {
            // `uint256(x)` / `uint256(x >> 255)` reinterpret the full 256-bit
            // word (lossless) — canonical Solady branchless abs, correct for
            // type(int256).min.
            // forge-lint: disable-next-line(unsafe-typecast)
            z = (uint256(x) + uint256(x >> 255)) ^ uint256(x >> 255);
        }
    }

    /// @notice CLZ-backed bit-length helper.
    /// @dev Uses `clz` for compatibility and deterministic behavior.
    function clz256(
        uint256 x
    ) internal pure returns (uint256 r) {
        r = clz_(x);
    }

    /// @notice Compatibility alias kept for compatibility surfaces.
    /// @dev No separate fallback path is currently needed on this deployment target.
    function clz256Compat(
        uint256 x
    ) internal pure returns (uint256 r) {
        return clz256(x);
    }

    /// @notice Count trailing zeros.
    /// @dev Returns 256 for zero.
    function ctz256(
        uint256 x
    ) internal pure returns (uint256 r) {
        return ffs(x);
    }

    /// @notice Index of most significant set bit.
    /// @dev Reverts for zero. Result is in [0, 255].
    function msbIndex(
        uint256 x
    ) internal pure returns (uint256 r) {
        if (x == 0) revert ZeroInput();
        return fls(x);
    }

    /// @notice Index of least significant set bit.
    /// @dev Reverts for zero. Result is in [0, 255].
    function lsbIndex(
        uint256 x
    ) internal pure returns (uint256 r) {
        if (x == 0) revert ZeroInput();
        return ffs(x);
    }

    /// @notice Number of bits needed to represent x.
    /// @dev `bitLength(0) == 0`.
    function bitLength(
        uint256 x
    ) internal pure returns (uint256 r) {
        if (x == 0) return 0;
        unchecked {
            return fls(x) + 1;
        }
    }

    /// @notice floor(log2(x)).
    function log2Floor(
        uint256 x
    ) internal pure returns (uint256 r) {
        if (x == 0) revert ZeroInput();
        return log2(x);
    }

    /// @notice ceil(log2(x)).
    /// @dev `log2Ceil(1) == 0`.
    function log2Ceil(
        uint256 x
    ) internal pure returns (uint256 r) {
        if (x == 0) revert ZeroInput();
        return log2Up(x);
    }

    /// @notice Returns true if x is a nonzero power of two.
    function isPowerOfTwo(
        uint256 x
    ) internal pure returns (bool) {
        return x != 0 && (x & (x - 1)) == 0;
    }

    /// @notice Highest set bit as a mask.
    /// @dev `floorPowerOfTwo(0) == 0`.
    function floorPowerOfTwo(
        uint256 x
    ) internal pure returns (uint256 r) {
        if (x == 0) return 0;

        unchecked {
            r = uint256(1) << fls(x);
        }
    }

    /// @notice Lowest set bit as a mask.
    /// @dev `lowestBit(0) == 0`.
    function lowestBit(
        uint256 x
    ) internal pure returns (uint256 r) {
        assembly ("memory-safe") {
            r := and(x, sub(0, x))
        }
    }

    /// @notice Smallest power of two >= x.
    /// @dev `nextPowerOfTwo(0) == 1`. Reverts if result would exceed 2^255.
    function nextPowerOfTwo(
        uint256 x
    ) internal pure returns (uint256 r) {
        if (x < 2) return 1;

        unchecked {
            uint256 n = bitLength(x - 1);
            if (n > 255) revert PowerOfTwoOverflow();
            r = uint256(1) << n;
        }
    }

    /// @notice Largest power of two <= x.
    /// @dev `previousPowerOfTwo(0) == 0`.
    function previousPowerOfTwo(
        uint256 x
    ) internal pure returns (uint256) {
        return floorPowerOfTwo(x);
    }

    /// @notice Overflow-safe average.
    function average(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        return avg(a, b);
    }

    /// @notice Computes base^exponent exactly for unsigned integers.
    /// @dev Returns 1 for exponent 0, including 0^0. Reverts on overflow.
    function pow(
        uint256 base,
        uint256 exponent
    ) internal pure returns (uint256) {
        return rpow(base, exponent, 1);
    }

    /// @notice Overflow-safe ceil(a / b).
    function ceilDiv(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        if (b == 0) revert DivisionByZero();
        return divUp(a, b);
    }

    /// @notice Minimum of two uint256 values.
    /// @dev Folded from Solady FixedPointMathLib (min).
    function min(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256 z) {
        assembly ("memory-safe") {
            z := xor(x, mul(xor(x, y), lt(y, x)))
        }
    }

    /// @notice Maximum of two uint256 values.
    /// @dev Folded from Solady FixedPointMathLib (max).
    function max(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256 z) {
        assembly ("memory-safe") {
            z := xor(x, mul(xor(x, y), gt(y, x)))
        }
    }

    /// @notice Clamp x into [minValue, maxValue].
    /// @dev Folded from Solady FixedPointMathLib (clamp). Reverts via `InvalidBounds` if lo > hi.
    function clamp(
        uint256 x,
        uint256 minValue,
        uint256 maxValue
    ) internal pure returns (uint256 z) {
        if (minValue > maxValue) revert InvalidBounds();
        assembly ("memory-safe") {
            z := xor(x, mul(xor(x, minValue), gt(minValue, x)))
            z := xor(z, mul(xor(z, maxValue), lt(maxValue, z)))
        }
    }

    /// @notice Computes floor(x * y / denominator) with full 512-bit precision.
    /// @dev Reverts if denominator is zero or result overflows uint256.
    function mulDiv(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        if (denominator == 0) revert DivisionByZero();
        return fullMulDiv(x, y, denominator);
    }

    /// @notice Computes ceil(x * y / denominator) with full 512-bit precision.
    function mulDivUp(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        if (denominator == 0) revert DivisionByZero();
        return fullMulDivUp(x, y, denominator);
    }

    /// @notice Computes floor(x * y / 2^shift) with full precision.
    function mulShr(
        uint256 x,
        uint256 y,
        uint8 shift
    ) internal pure returns (uint256) {
        return mulDiv(x, y, uint256(1) << shift);
    }

    /// @notice Computes ceil(x * y / 2^shift) with full precision.
    function mulShrUp(
        uint256 x,
        uint256 y,
        uint8 shift
    ) internal pure returns (uint256) {
        return mulDivUp(x, y, uint256(1) << shift);
    }

    /// @notice Computes floor(x * y / 1e18) with full precision.
    function mulWadDown(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256) {
        return mulDiv(x, y, WAD_UINT);
    }

    /// @notice Computes ceil(x * y / 1e18) with full precision.
    function mulWadUp(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256) {
        return mulDivUp(x, y, WAD_UINT);
    }

    /// @notice Computes floor(x * 1e18 / y) with full precision.
    function divWadDown(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256) {
        return mulDiv(x, WAD_UINT, y);
    }

    /// @notice Computes ceil(x * 1e18 / y) with full precision.
    function divWadUp(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256) {
        return mulDivUp(x, WAD_UINT, y);
    }

    /// @notice Computes floor(x * y / Q96) with full precision.
    function mulQ96Down(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256) {
        return mulDiv(x, y, Q96);
    }

    /// @notice Computes ceil(x * y / Q96) with full precision.
    function mulQ96Up(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256) {
        return mulDivUp(x, y, Q96);
    }

    /// @notice Computes floor(x * Q96 / y) with full precision.
    function divQ96Down(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256) {
        return mulDiv(x, Q96, y);
    }

    /// @notice Computes ceil(x * Q96 / y) with full precision.
    function divQ96Up(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256) {
        return mulDivUp(x, Q96, y);
    }

    /// @notice Computes floor(x * y / Q128) with full precision.
    function mulQ128Down(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256) {
        return mulDiv(x, y, Q128);
    }

    /// @notice Computes ceil(x * y / Q128) with full precision.
    function mulQ128Up(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256) {
        return mulDivUp(x, y, Q128);
    }

    /// @notice Computes floor(x * Q128 / y) with full precision.
    function divQ128Down(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256) {
        return mulDiv(x, Q128, y);
    }

    /// @notice Computes ceil(x * Q128 / y) with full precision.
    function divQ128Up(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256) {
        return mulDivUp(x, Q128, y);
    }

    /// @notice Converts Q96 fixed-point value to WAD.
    function q96ToWad(
        uint256 x
    ) internal pure returns (uint256) {
        return mulDiv(x, WAD_UINT, Q96);
    }

    /// @notice Converts WAD fixed-point value to Q96.
    function wadToQ96(
        uint256 x
    ) internal pure returns (uint256) {
        return mulDiv(x, Q96, WAD_UINT);
    }

    /// @notice Converts Q128 fixed-point value to WAD.
    function q128ToWad(
        uint256 x
    ) internal pure returns (uint256) {
        return mulDiv(x, WAD_UINT, Q128);
    }

    /// @notice Converts WAD fixed-point value to Q128.
    function wadToQ128(
        uint256 x
    ) internal pure returns (uint256) {
        return mulDiv(x, Q128, WAD_UINT);
    }

    /// @notice Computes floor(abs(x) * abs(y) / abs(denominator)), then reapplies sign.
    /// @dev Supports `type(int256).min` magnitude.
    function signedMulDiv(
        int256 x,
        int256 y,
        int256 denominator
    ) internal pure returns (int256 result) {
        if (denominator == 0) revert DivisionByZero();

        bool negative = (x < 0) != (y < 0);
        negative = negative != (denominator < 0);

        uint256 ax = abs(x);
        uint256 ay = abs(y);
        uint256 ad = abs(denominator);
        uint256 r = mulDiv(ax, ay, ad);

        if (negative) {
            if (r > INT256_MIN_ABS) revert SignedMathOverflow();
            if (r == INT256_MIN_ABS) return type(int256).min;
            return -checkedInt256(r);
        }

        if (r > uint256(type(int256).max)) revert SignedMathOverflow();
        result = checkedInt256(r);
    }

    /// @notice Signed floor(x * y / 1e18) with full precision.
    function signedMulWadDown(
        int256 x,
        int256 y
    ) internal pure returns (int256) {
        return signedMulDiv(x, y, WAD_INT);
    }

    /// @notice Signed floor(x * 1e18 / y) with full precision.
    function signedDivWadDown(
        int256 x,
        int256 y
    ) internal pure returns (int256) {
        return signedMulDiv(x, WAD_INT, y);
    }

    /// @notice Convert a range-checked unsigned magnitude to int256 without truncation.
    function checkedInt256(
        uint256 value
    ) internal pure returns (int256 result) {
        if (value > uint256(type(int256).max)) revert SignedMathOverflow();
        assembly ("memory-safe") {
            result := value
        }
    }

    /// @notice Integer square root, rounded down.
    /// @dev Uses CLZ-derived initial estimate and Newton refinement.
    ///      Folded from Solady FixedPointMathLib (sqrt).
    function sqrt(
        uint256 x
    ) internal pure returns (uint256 z) {
        assembly ("memory-safe") {
            // Step 1: Get the bit position of the most significant bit
            // n = floor(log2(x))
            // For x ≈ 2^n, we know sqrt(x) ≈ 2^(n/2)
            // We use (n+1)/2 instead of n/2 to round up slightly
            // This gives a better initial approximation. This seed gives
            // ε₁ = 0.0607 after one Babylonian step for all inputs. With
            // ε_{n+1} ≈ ε²/2, 6 steps yield 2⁻¹⁶⁰ relative error (>128 correct
            // bits).
            //
            // Formula: z = 2^((n+1)/2) = 2^(floor((n+1)/2))
            // Implemented as: z = 1 << ((n+1) >> 1)
            z := shl(shr(1, sub(256, clz(x))), 1)

            // 6 Babylonian steps; z = (x/z + z) / 2
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))

            // If `x+1` is a perfect square, the Babylonian method cycles between
            // `floor(sqrt(x))` and `ceil(sqrt(x))`. This statement ensures we return floor.
            // See: https://en.wikipedia.org/wiki/Integer_square_root#Using_only_integer_division
            z := sub(z, lt(div(x, z), z))
        }
    }

    /// @notice Integer square root, rounded up.
    function sqrtUp(
        uint256 x
    ) internal pure returns (uint256 z) {
        z = sqrt(x);

        unchecked {
            if (z * z < x) ++z;
        }
    }

    /// @notice Compact magnitude bucket for reserves/liquidity.
    /// @dev Returns floor(log2(x)); returns 0 for x == 0.
    function magnitudeBucket(
        uint256 x
    ) internal pure returns (uint256) {
        if (x == 0) return 0;
        return log2Floor(x);
    }

    /// @notice Fast reserve imbalance score.
    /// @dev Higher means more imbalance. Uses log2 distance, not price-accurate math.
    function reserveImbalanceBucket(
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256) {
        if (reserveA == 0 || reserveB == 0) return type(uint256).max;

        uint256 a = log2Floor(reserveA);
        uint256 b = log2Floor(reserveB);
        return a > b ? a - b : b - a;
    }

    /// @notice Returns true if reserves are too small or too imbalanced for expensive simulation.
    function rejectByReserveShape(
        uint256 reserveA,
        uint256 reserveB,
        uint256 minBitLength,
        uint256 maxImbalanceBucket
    ) internal pure returns (bool) {
        if (bitLength(reserveA) < minBitLength) return true;
        if (bitLength(reserveB) < minBitLength) return true;
        return reserveImbalanceBucket(reserveA, reserveB) > maxImbalanceBucket;
    }

    /// @notice Fast approximate liquidity class for ranking candidate pools.
    /// @dev Not a price model. Use only for pre-filtering.
    function liquidityClass(
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256) {
        uint256 minReserve = min(reserveA, reserveB);
        return bitLength(minReserve);
    }

    /// @notice Returns the byte offset of the first nonzero byte in a word.
    /// @dev Returns 32 for zero.
    function firstNonZeroByteOffset(
        uint256 x
    ) internal pure returns (uint256) {
        return clz256(x) >> 3;
    }

    /// @notice Returns the number of zero bytes before the first nonzero byte.
    /// @dev Alias for calldata/bitmap compression scanners.
    function leadingZeroBytes(
        uint256 x
    ) internal pure returns (uint256) {
        return clz256(x) >> 3;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*       PRIVATE PRIMITIVES (folded from Solady libraries)    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Find last set: index of the MSB of `x` from the LSB. Returns 256 if `x` is zero.
    function fls(
        uint256 x
    ) private pure returns (uint256 r) {
        assembly ("memory-safe") {
            r := xor(xor(255, clz(x)), mul(255, iszero(x)))
        }
    }

    /// @dev Find first set (count trailing zeros): index of the LSB. Returns 256 if `x` is zero.
    function ffs(
        uint256 x
    ) private pure returns (uint256 r) {
        assembly ("memory-safe") {
            // Isolate the least significant bit.
            x := and(x, add(not(x), 1))
            r := xor(xor(255, clz(x)), mul(255, iszero(x)))
        }
    }

    /// @dev Count leading zeros via the native EIP-7939 `clz` opcode. Returns 256 if `x` is zero.
    function clz_(
        uint256 x
    ) private pure returns (uint256 r) {
        assembly ("memory-safe") {
            r := clz(x)
        }
    }

    /// @dev Returns the log2 of `x`.
    /// Equivalent to computing the index of the most significant bit (MSB) of `x`.
    /// Returns 0 if `x` is zero.
    function log2(
        uint256 x
    ) private pure returns (uint256 r) {
        assembly ("memory-safe") {
            r := sub(255, clz(or(x, 1)))
        }
    }

    /// @dev Returns the log2 of `x`, rounded up.
    /// Returns 0 if `x` is zero.
    function log2Up(
        uint256 x
    ) private pure returns (uint256 r) {
        r = log2(x);
        assembly ("memory-safe") {
            r := add(r, lt(shl(r, 1), x))
        }
    }

    /// @dev Returns the average of `x` and `y`. Rounds towards zero.
    function avg(
        uint256 x,
        uint256 y
    ) private pure returns (uint256 z) {
        unchecked {
            z = (x & y) + ((x ^ y) >> 1);
        }
    }

    /// @dev Exponentiate `x` to `y` by squaring, denominated in base `b`.
    /// Reverts if the computation overflows.
    function rpow(
        uint256 x,
        uint256 y,
        uint256 b
    ) private pure returns (uint256 z) {
        assembly ("memory-safe") {
            z := mul(b, iszero(y)) // `0 ** 0 = 1`. Otherwise, `0 ** n = 0`.
            if x {
                z := xor(b, mul(xor(b, x), and(y, 1))) // `z = isEven(y) ? scale : x`
                let half := shr(1, b) // Divide `b` by 2.
                // Divide `y` by 2 every iteration.
                for { y := shr(1, y) } y { y := shr(1, y) } {
                    let xx := mul(x, x) // Store x squared.
                    let xxRound := add(xx, half) // Round to the nearest number.
                    // Revert if `xx + half` overflowed, or if `x ** 2` overflows.
                    if or(lt(xxRound, xx), shr(128, x)) {
                        mstore(0x00, 0x49f7642b) // `RPowOverflow()`.
                        revert(0x1c, 0x04)
                    }
                    x := div(xxRound, b) // Set `x` to scaled `xxRound`.
                    // If `y` is odd:
                    if and(y, 1) {
                        let zx := mul(z, x) // Compute `z * x`.
                        let zxRound := add(zx, half) // Round to the nearest number.
                        // If `z * x` overflowed or `zx + half` overflowed:
                        if or(xor(div(zx, x), z), lt(zxRound, zx)) {
                            // Revert if `x` is non-zero.
                            if x {
                                mstore(0x00, 0x49f7642b) // `RPowOverflow()`.
                                revert(0x1c, 0x04)
                            }
                        }
                        z := div(zxRound, b) // Return properly scaled `zxRound`.
                    }
                }
            }
        }
    }

    /// @dev Returns `ceil(x / d)`.
    /// Reverts if `d` is zero.
    function divUp(
        uint256 x,
        uint256 d
    ) private pure returns (uint256 z) {
        assembly ("memory-safe") {
            if iszero(d) {
                mstore(0x00, 0x65244e4e) // `DivFailed()`.
                revert(0x1c, 0x04)
            }
            z := add(iszero(iszero(mod(x, d))), div(x, d))
        }
    }

    /// @dev Calculates `floor(x * y / d)` with full precision.
    /// Throws if result overflows a uint256 or when `d` is zero.
    /// Credit to Remco Bloemen under MIT license: https://2π.com/21/muldiv
    function fullMulDiv(
        uint256 x,
        uint256 y,
        uint256 d
    ) private pure returns (uint256 z) {
        assembly ("memory-safe") {
            // 512-bit multiply `[p1 p0] = x * y`.
            // Compute the product mod `2**256` and mod `2**256 - 1`
            // then use the Chinese Remainder Theorem to reconstruct
            // the 512 bit result. The result is stored in two 256
            // variables such that `product = p1 * 2**256 + p0`.

            // Temporarily use `z` as `p0` to save gas.
            z := mul(x, y) // Lower 256 bits of `x * y`.
            for { } 1 { } {
                // If overflows.
                if iszero(mul(or(iszero(x), eq(div(z, x), y)), d)) {
                    let mm := mulmod(x, y, not(0))
                    let p1 := sub(mm, add(z, lt(mm, z))) // Upper 256 bits of `x * y`.

                    /*------------------- 512 by 256 division --------------------*/

                    // Make division exact by subtracting the remainder from `[p1 p0]`.
                    let r := mulmod(x, y, d) // Compute remainder using mulmod.
                    let t := and(d, sub(0, d)) // The least significant bit of `d`. `t >= 1`.
                    // Make sure `z` is less than `2**256`. Also prevents `d == 0`.
                    // Placing the check here seems to give more optimal stack operations.
                    if iszero(gt(d, p1)) {
                        mstore(0x00, 0xae47f702) // `FullMulDivFailed()`.
                        revert(0x1c, 0x04)
                    }
                    d := div(d, t) // Divide `d` by `t`, which is a power of two.
                    // Invert `d mod 2**256`
                    // Now that `d` is an odd number, it has an inverse
                    // modulo `2**256` such that `d * inv = 1 mod 2**256`.
                    // Compute the inverse by starting with a seed that is correct
                    // correct for four bits. That is, `d * inv = 1 mod 2**4`.
                    let inv := xor(2, mul(3, d))
                    // Now use Newton-Raphson iteration to improve the precision.
                    // Thanks to Hensel's lifting lemma, this also works in modular
                    // arithmetic, doubling the correct bits in each step.
                    inv := mul(inv, sub(2, mul(d, inv))) // inverse mod 2**8
                    inv := mul(inv, sub(2, mul(d, inv))) // inverse mod 2**16
                    inv := mul(inv, sub(2, mul(d, inv))) // inverse mod 2**32
                    inv := mul(inv, sub(2, mul(d, inv))) // inverse mod 2**64
                    inv := mul(inv, sub(2, mul(d, inv))) // inverse mod 2**128
                    z := mul(
                        // Divide [p1 p0] by the factors of two.
                        // Shift in bits from `p1` into `p0`. For this we need
                        // to flip `t` such that it is `2**256 / t`.
                        or(mul(sub(p1, gt(r, z)), add(div(sub(0, t), t), 1)), div(sub(z, r), t)),
                        mul(sub(2, mul(d, inv)), inv) // inverse mod 2**256
                    )
                    break
                }
                z := div(z, d)
                break
            }
        }
    }

    /// @dev Calculates `floor(x * y / d)` with full precision, rounded up.
    /// Throws if result overflows a uint256 or when `d` is zero.
    /// Credit to Uniswap-v3-core under MIT license:
    /// https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/FullMath.sol
    function fullMulDivUp(
        uint256 x,
        uint256 y,
        uint256 d
    ) private pure returns (uint256 z) {
        z = fullMulDiv(x, y, d);
        assembly ("memory-safe") {
            if mulmod(x, y, d) {
                z := add(z, 1)
                if iszero(z) {
                    mstore(0x00, 0xae47f702) // `FullMulDivFailed()`.
                    revert(0x1c, 0x04)
                }
            }
        }
    }
}
