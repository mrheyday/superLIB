// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title BitMath
/// @notice Self-contained optimized bitwise operations for Solidity 0.8.34 (Osaka).
/// @dev Single-library build with no external imports: the Solady `LibBit` primitives
///      this library depends on are inlined as private helpers, and leading-zero counts
///      are backed by the native EIP-7939 `clz` opcode (osaka target).
///      Bit-twiddling primitives derived from Solady (MIT,
///      https://github.com/vectorized/solady).
library BitMath {
    /// @notice Zero is not a valid input for `mostSignificantBit`.
    error BitMath__ZeroInput();

    /// @notice Returns the index of the most significant bit of x.
    /// @param x The value to scan.
    /// @return r The index of the MSB (0-255).
    /// @dev Reverts with `BitMath__ZeroInput` if x is 0.
    function mostSignificantBit(
        uint256 x
    ) internal pure returns (uint8 r) {
        if (x == 0) revert BitMath__ZeroInput();
        // Safe because for x != 0 the result is in [0, 255].
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint8(fls(x));
    }

    /// @notice Returns the number of leading zeros in x.
    /// @param x The value to scan.
    /// @return r The number of leading zeros (0-256).
    /// @dev Named `leadingZeros` rather than `clz` to avoid visual shadowing of the Yul
    ///      `clz` opcode (EIP-7939) used by the private `clz_` helper below.
    function leadingZeros(
        uint256 x
    ) internal pure returns (uint256 r) {
        r = clz_(x);
    }

    /// @notice Returns the number of trailing zeros in x.
    /// @param x The value to scan.
    /// @return r The number of trailing zeros (0-256).
    function trailingZeros(
        uint256 x
    ) internal pure returns (uint256 r) {
        r = ffs(x);
    }

    /// @notice Returns the number of set bits in x.
    /// @param x The value to scan.
    /// @return r The number of one bits (0-256).
    function popCount(
        uint256 x
    ) internal pure returns (uint256 r) {
        assembly ("memory-safe") {
            let max := not(0)
            let isMax := eq(x, max)
            x := sub(x, and(shr(1, x), div(max, 3)))
            x := add(and(x, div(max, 5)), and(shr(2, x), div(max, 5)))
            x := and(add(x, shr(4, x)), div(max, 17))
            r := or(shl(8, isMax), shr(248, mul(x, div(max, 255))))
        }
    }

    /// @notice Returns the number of zero bytes in x.
    /// @param x The 256-bit word to scan.
    /// @return r The count of zero bytes (0-32).
    function countZeroBytes(
        uint256 x
    ) internal pure returns (uint256 r) {
        assembly ("memory-safe") {
            let m := 0x7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f
            r := byte(0, mul(shr(7, not(m)), shr(7, not(or(or(add(and(x, m), m), x), m)))))
        }
    }

    /// @notice Returns x with its bit order reversed.
    /// @param x The value to reverse.
    /// @return r The bit-reversed value.
    function reverseBits(
        uint256 x
    ) internal pure returns (uint256 r) {
        uint256 m0 = 0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f;
        uint256 m1 = m0 ^ (m0 << 2);
        uint256 m2 = m1 ^ (m1 << 1);
        r = reverseBytes(x);
        r = (m2 & (r >> 1)) | ((m2 & r) << 1);
        r = (m1 & (r >> 2)) | ((m1 & r) << 2);
        r = (m0 & (r >> 4)) | ((m0 & r) << 4);
    }

    /// @notice Returns x with its byte order reversed.
    /// @param x The value to reverse.
    /// @return r The byte-reversed value.
    function reverseBytes(
        uint256 x
    ) internal pure returns (uint256 r) {
        unchecked {
            // Computing masks on-the-fly reduces bytecode size by about 200 bytes.
            uint256 m0 = 0x100000000000000000000000000000001 * (~toUint(x == uint256(0)) >> 192);
            uint256 m1 = m0 ^ (m0 << 32);
            uint256 m2 = m1 ^ (m1 << 16);
            uint256 m3 = m2 ^ (m2 << 8);
            r = (m3 & (x >> 8)) | ((m3 & x) << 8);
            r = (m2 & (r >> 16)) | ((m2 & r) << 16);
            r = (m1 & (r >> 32)) | ((m1 & r) << 32);
            r = (m0 & (r >> 64)) | ((m0 & r) << 64);
            r = (r >> 128) | (r << 128);
        }
    }

    /// @notice Returns the common most-significant bit prefix of x and y.
    /// @param x The first value.
    /// @param y The second value.
    /// @return r The shared high bits of x and y, with the low differing bits zeroed.
    function commonBitPrefix(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256 r) {
        unchecked {
            uint256 s = 256 - clz_(x ^ y);
            r = (x >> s) << s;
        }
    }

    /// @notice Expands each byte of s into two nibble-bytes.
    /// @param s The input byte string.
    /// @return result The nibble-expanded byte string (length `2 * s.length`).
    function toNibbles(
        bytes memory s
    ) internal pure returns (bytes memory result) {
        assembly ("memory-safe") {
            result := mload(0x40)
            let n := mload(s)
            mstore(result, add(n, n)) // Store the new length.
            s := add(s, 0x20)
            let o := add(result, 0x20)
            // forgefmt: disable-next-item
            for { let i := 0 } lt(i, n) { i := add(i, 0x10) } {
                let x := shr(128, mload(add(s, i)))
                x := and(0x0000000000000000ffffffffffffffff0000000000000000ffffffffffffffff, or(shl(64, x), x))
                x := and(0x00000000ffffffff00000000ffffffff00000000ffffffff00000000ffffffff, or(shl(32, x), x))
                x := and(0x0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff, or(shl(16, x), x))
                x := and(0x00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff, or(shl(8, x), x))
                mstore(add(o, add(i, i)),
                    and(0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f, or(shl(4, x), x)))
            }
            mstore(add(o, mload(result)), 0) // Zeroize slot after result.
            mstore(0x40, add(0x40, add(o, mload(result)))) // Allocate memory.
        }
    }

    /// @notice Returns the number of leading zeros in an 8-bit value.
    function leadingZerosUint8(
        uint8 x
    ) internal pure returns (uint8 r) {
        unchecked {
            // Safe because the result for an 8-bit input is in [0, 8].
            // forge-lint: disable-next-line(unsafe-typecast)
            r = uint8(clz_(uint256(x)) - 248);
        }
    }

    /// @notice Returns the number of leading zeros in a 16-bit value.
    function leadingZerosUint16(
        uint16 x
    ) internal pure returns (uint16 r) {
        unchecked {
            // Safe because the result for a 16-bit input is in [0, 16].
            // forge-lint: disable-next-line(unsafe-typecast)
            r = uint16(clz_(uint256(x)) - 240);
        }
    }

    /// @notice Returns the number of leading zeros in a 32-bit value.
    function leadingZerosUint32(
        uint32 x
    ) internal pure returns (uint32 r) {
        unchecked {
            // Safe because the result for a 32-bit input is in [0, 32].
            // forge-lint: disable-next-line(unsafe-typecast)
            r = uint32(clz_(uint256(x)) - 224);
        }
    }

    /// @notice Returns the number of leading zeros in a 64-bit value.
    function leadingZerosUint64(
        uint64 x
    ) internal pure returns (uint64 r) {
        unchecked {
            // Safe because the result for a 64-bit input is in [0, 64].
            // forge-lint: disable-next-line(unsafe-typecast)
            r = uint64(clz_(uint256(x)) - 192);
        }
    }

    /// @notice Returns leading-zero counts for every uint256 input.
    function batchLeadingZeros(
        uint256[] memory inputs
    ) internal pure returns (uint256[] memory results) {
        uint256 length = inputs.length;
        results = new uint256[](length);
        for (uint256 i; i < length;) {
            results[i] = leadingZeros(inputs[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Returns trailing-zero counts for every uint256 input.
    function batchTrailingZeros(
        uint256[] memory inputs
    ) internal pure returns (uint256[] memory results) {
        uint256 length = inputs.length;
        results = new uint256[](length);
        for (uint256 i; i < length;) {
            results[i] = trailingZeros(inputs[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Returns set-bit counts for every uint256 input.
    function batchPopCount(
        uint256[] memory inputs
    ) internal pure returns (uint256[] memory results) {
        uint256 length = inputs.length;
        results = new uint256[](length);
        for (uint256 i; i < length;) {
            results[i] = popCount(inputs[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Returns leading-zero counts for every uint8 input.
    function batchLeadingZerosUint8(
        uint8[] memory inputs
    ) internal pure returns (uint8[] memory results) {
        uint256 length = inputs.length;
        results = new uint8[](length);
        for (uint256 i; i < length;) {
            results[i] = leadingZerosUint8(inputs[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Returns leading-zero counts for every uint16 input.
    function batchLeadingZerosUint16(
        uint16[] memory inputs
    ) internal pure returns (uint16[] memory results) {
        uint256 length = inputs.length;
        results = new uint16[](length);
        for (uint256 i; i < length;) {
            results[i] = leadingZerosUint16(inputs[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Returns leading-zero counts for every uint32 input.
    function batchLeadingZerosUint32(
        uint32[] memory inputs
    ) internal pure returns (uint32[] memory results) {
        uint256 length = inputs.length;
        results = new uint32[](length);
        for (uint256 i; i < length;) {
            results[i] = leadingZerosUint32(inputs[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Returns leading-zero counts for every uint64 input.
    function batchLeadingZerosUint64(
        uint64[] memory inputs
    ) internal pure returns (uint64[] memory results) {
        uint256 length = inputs.length;
        results = new uint64[](length);
        for (uint256 i; i < length;) {
            results[i] = leadingZerosUint64(inputs[i]);
            unchecked {
                ++i;
            }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*       PRIVATE PRIMITIVES (inlined from Solady LibBit)      */
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

    /// @dev Returns 1 if `b` is true, else 0.
    function toUint(
        bool b
    ) private pure returns (uint256 z) {
        assembly ("memory-safe") {
            z := iszero(iszero(b))
        }
    }
}
