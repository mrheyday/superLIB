// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title BLSLib — EIP-2537 BLS12-381 Signature Verification Library
/// @notice Gas-efficient BLS signature verification using the BLS12-381 precompiles.
///         Follows the "dumb contracts, smart Rust" principle: Rust computes all
///         uncompressed coordinates and hash-to-curve points; the contract only performs
///         the pairing check via a single staticcall.
///
/// @dev EIP-2537 precompile layout (Pectra):
///      0x0b  G1ADD           — add two G1 points (256 bytes in → 128 bytes out)
///      0x0c  G1MSM           — multi-scalar multiplication on G1
///      0x0d  G2ADD           — add two G2 points (512 bytes in → 256 bytes out)
///      0x0e  G2MSM           — multi-scalar multiplication on G2
///      0x0f  PAIRING         — bilinear pairing check (N×384 bytes in → 32 bytes out)
///      0x10  MAP_FP_TO_G1    — map field element to G1
///      0x11  MAP_FP2_TO_G2   — map Fp2 element to G2
///
///      BLS signature verification uses the PAIRING precompile (0x0f):
///      Given pubkey P ∈ G1, message hash H(m) ∈ G2, signature σ ∈ G2, generator G1:
///        e(P, H(m)) · e(−G1, σ) = 1  (product of pairings equals identity)
///
///      The contract receives 2 pairs × 384 bytes = 768 bytes of pairing input from Rust.
///      Rust is responsible for:
///        1. Decompressing the 48-byte pubkey to 128-byte uncompressed G1
///        2. Computing hash-to-G2 of the bid message (256-byte uncompressed G2)
///        3. Negating the G1 generator (128-byte uncompressed G1)
///        4. Decompressing the 96-byte signature to 256-byte uncompressed G2
///        5. Packing: [P || H(m) || (−G1) || σ] = 768 bytes
///
/// @custom:eip EIP-2537: BLS12-381 precompiles
/// @custom:security Pairing check is cryptographically binding — no on-chain trust assumptions.
library BLSLib {
    // ═══════════════════════════════════════════════════════════════════════════
    //                    EIP-2537 PRECOMPILE ADDRESSES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev BLS12-381 G1ADD precompile
    address internal constant BLS_G1ADD = address(0x0b);

    /// @dev BLS12-381 G1MSM precompile (multi-scalar multiplication)
    address internal constant BLS_G1MSM = address(0x0c);

    /// @dev BLS12-381 G2ADD precompile
    address internal constant BLS_G2ADD = address(0x0d);

    /// @dev BLS12-381 G2MSM precompile (multi-scalar multiplication)
    address internal constant BLS_G2MSM = address(0x0e);

    /// @dev BLS12-381 PAIRING precompile
    address internal constant BLS_PAIRING = address(0x0f);

    /// @dev BLS12-381 MAP_FP_TO_G1 precompile
    address internal constant BLS_MAP_FP_TO_G1 = address(0x10);

    /// @dev BLS12-381 MAP_FP2_TO_G2 precompile
    address internal constant BLS_MAP_FP2_TO_G2 = address(0x11);

    // ═══════════════════════════════════════════════════════════════════════════
    //                    CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Size of one (G1, G2) pair for the pairing precompile
    ///      G1 uncompressed: 128 bytes, G2 uncompressed: 256 bytes → 384 bytes per pair
    uint256 internal constant PAIR_SIZE = 384;

    /// @dev Size of a single BLS signature verification: 2 pairs = 768 bytes
    ///      Pair 1: (pubkey, hash_to_g2)       — verifier's key + message hash
    ///      Pair 2: (neg_generator, signature)  — negated G1 generator + BLS sig
    uint256 internal constant SINGLE_VERIFY_SIZE = 768;

    // ═══════════════════════════════════════════════════════════════════════════
    //                    ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Pairing precompile returned 0 (invalid) or call failed
    error BLSSignatureInvalid();

    /// @dev Input length doesn't match expected pairing format
    error BLSInputLengthMismatch();

    // ═══════════════════════════════════════════════════════════════════════════
    //                    SINGLE SIGNATURE VERIFICATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Verify a single BLS12-381 signature using the pairing precompile
    /// @dev Expects exactly 768 bytes: [pubkey(128) || hash_to_g2(256) || neg_g1(128) || sig(256)]
    ///      Rust packs this from: compressed_pubkey(48B) + message + compressed_sig(96B)
    ///      Returns false if the pairing check fails or the precompile reverts.
    /// @param pairingInput Pre-computed pairing input from Rust (768 bytes)
    /// @return valid True if the BLS signature is valid
    function verifySingle(bytes calldata pairingInput) internal view returns (bool valid) {
        if (pairingInput.length != SINGLE_VERIFY_SIZE) revert BLSInputLengthMismatch();

        assembly ("memory-safe") {
            let ptr := mload(0x40)
            calldatacopy(ptr, pairingInput.offset, 768)
            // BLS_PAIRING at 0x0f: returns 1 if product of pairings = identity
            let success := staticcall(gas(), 0x0f, ptr, 768, ptr, 0x20)
            valid := and(success, eq(mload(ptr), 1))
        }
    }

    /// @notice Verify a single BLS signature, reverting on failure
    /// @param pairingInput Pre-computed pairing input (768 bytes)
    function verifySingleOrRevert(bytes calldata pairingInput) internal view {
        if (!verifySingle(pairingInput)) revert BLSSignatureInvalid();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                    AGGREGATED SIGNATURE VERIFICATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Verify an aggregated BLS signature over multiple messages
    /// @dev Input: N pairs of (G1_point, G2_point), each 384 bytes = N × 384 total.
    ///      Rust constructs the aggregation and provides all pairs.
    ///      Verification: product of all e(G1_i, G2_i) == 1
    /// @param pairingInput ABI-packed pairing pairs
    /// @param numPairs Number of (G1, G2) pairs
    /// @return valid True if the aggregated pairing check passes
    function verifyAggregate(bytes calldata pairingInput, uint256 numPairs) internal view returns (bool valid) {
        uint256 expectedLen = numPairs * PAIR_SIZE;
        if (pairingInput.length != expectedLen) revert BLSInputLengthMismatch();

        assembly ("memory-safe") {
            let ptr := mload(0x40)
            calldatacopy(ptr, pairingInput.offset, expectedLen)
            let success := staticcall(gas(), 0x0f, ptr, expectedLen, ptr, 0x20)
            valid := and(success, eq(mload(ptr), 1))
        }
    }

    /// @notice Verify aggregated BLS signature, reverting on failure
    /// @param pairingInput ABI-packed pairing pairs
    /// @param numPairs Number of pairs
    function verifyAggregateOrRevert(bytes calldata pairingInput, uint256 numPairs) internal view {
        if (!verifyAggregate(pairingInput, numPairs)) revert BLSSignatureInvalid();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                    G1 / G2 POINT OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Add two G1 points using the G1ADD precompile
    /// @param p1 First G1 point (128 bytes uncompressed)
    /// @param p2 Second G1 point (128 bytes uncompressed)
    /// @return result Resulting G1 point (128 bytes)
    function g1Add(bytes calldata p1, bytes calldata p2) internal view returns (bytes memory result) {
        result = new bytes(128);
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            calldatacopy(ptr, p1.offset, 0x80)
            calldatacopy(add(ptr, 0x80), p2.offset, 0x80)
            let success := staticcall(gas(), 0x0b, ptr, 0x100, add(result, 0x20), 0x80)
            if iszero(success) {
                // BLSSignatureInvalid()
                mstore(0x00, 0x10e416aa)
                revert(0x1c, 0x04)
            }
        }
    }

    /// @notice Add two G2 points using the G2ADD precompile
    /// @param p1 First G2 point (256 bytes uncompressed)
    /// @param p2 Second G2 point (256 bytes uncompressed)
    /// @return result Resulting G2 point (256 bytes)
    function g2Add(bytes calldata p1, bytes calldata p2) internal view returns (bytes memory result) {
        result = new bytes(256);
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            calldatacopy(ptr, p1.offset, 0x100)
            calldatacopy(add(ptr, 0x100), p2.offset, 0x100)
            let success := staticcall(gas(), 0x0d, ptr, 0x200, add(result, 0x20), 0x100)
            if iszero(success) {
                // BLSSignatureInvalid()
                mstore(0x00, 0x10e416aa)
                revert(0x1c, 0x04)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                    PRECOMPILE AVAILABILITY CHECK
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Check if EIP-2537 BLS precompiles are available on this chain
    /// @dev Calls G1ADD with the identity point (zero) — succeeds only if precompile exists.
    ///      Costs ~500 gas for the check.
    /// @return available True if the BLS precompiles respond
    function isAvailable() internal view returns (bool available) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            // Zero-initialize 256 bytes (two zero G1 points)
            // Identity + Identity should return Identity if precompile exists
            mstore(ptr, 0)
            mstore(add(ptr, 0x20), 0)
            mstore(add(ptr, 0x40), 0)
            mstore(add(ptr, 0x60), 0)
            mstore(add(ptr, 0x80), 0)
            mstore(add(ptr, 0xa0), 0)
            mstore(add(ptr, 0xc0), 0)
            mstore(add(ptr, 0xe0), 0)
            // Call G1ADD with two identity points
            available := staticcall(gas(), 0x0b, ptr, 0x100, ptr, 0x80)
        }
    }
}
