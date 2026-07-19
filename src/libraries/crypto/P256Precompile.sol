// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title P256Precompile
/// @notice EIP-7951 P256VERIFY precompile utilities: cached availability detection,
///         curve/range validation, and raw-bytes verification.
/// @dev For "verify with automatic native-precompile + fallback" semantics, call
///      Solady's `P256.verifySignature` (solady/utils/P256.sol) directly — it already
///      implements that path, so this library does not re-wrap it.
/// @dev Native secp256r1 (P-256) signature verification at address 0x100
/// @dev Osaka EVM: 6,900 gas vs ~100,000+ gas for pure Solidity
///
/// Use cases:
/// - Apple Secure Enclave signing
/// - Android Keystore signing
/// - WebAuthn/FIDO2 passkeys
/// - Hardware Security Modules (HSMs)
/// - Trusted Execution Environments (TEEs)
library P256Precompile {
    /// @dev P256VERIFY precompile address (EIP-7951)
    address internal constant P256_VERIFY = address(0x100);

    // slither-disable-start too-many-digits
    /// @dev secp256r1 curve order n
    uint256 internal constant N =
        0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551;

    /// @dev secp256r1 field modulus p
    uint256 internal constant P =
        0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF;

    /// @dev Curve coefficient a = -3 mod p
    uint256 internal constant A =
        0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFC;

    /// @dev Curve coefficient b
    uint256 internal constant B =
        0x5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B;
    // slither-disable-end too-many-digits

    /// @dev Cached precompile availability (0 = unknown, 1 = available, 2 = unavailable)
    /// Uses a fixed storage slot to avoid collisions
    bytes32 private constant PRECOMPILE_STATUS_SLOT = keccak256("p256precompile.status.slot");

    // ============== Events ==============

    event P256PrecompileDetected(bool available);

    // ============== Errors ==============

    error InvalidSignatureLength();
    error InvalidPublicKey();
    error SignatureVerificationFailed();

    // ============== Detection ==============

    /// @notice Check if native P256VERIFY precompile is available
    /// @dev Tests with a known valid signature
    /// @return available True if precompile is available
    function isPrecompileAvailable() internal returns (bool available) {
        // Check cached status first
        uint256 status;
        bytes32 slot = PRECOMPILE_STATUS_SLOT;
        assembly {
            status := sload(slot)
        }

        if (status == 1) return true;
        if (status == 2) return false;

        // Test with a known valid P-256 signature
        // This is a pre-computed valid signature for testing
        bytes32 testHash = 0xbb5a52f42f9c9261ed4361f59422a1e30036e7c32b270c8807a419feca605023;
        bytes32 testR = 0x2ba3a8be6b94d5ec80a6d9d1190a436effe50d85a1eee859b8cc6af9bd5c2e18;
        bytes32 testS = 0x4cd60b855d442f5b3c7b11eb6c4e0ae7525fe710fab9aa7c77a67f79e6fadd76;
        bytes32 testQx = 0x2927b10512bae3eddcfe467828128bad2903269919f7086069c8c4df6c732838;
        bytes32 testQy = 0xc7787964eaac00e5921fb1498a60f4606766b3d9685001558d1a974e7341513e;

        // Try calling the precompile
        (bool success, bytes memory result) =
            P256_VERIFY.staticcall(abi.encodePacked(testHash, testR, testS, testQx, testQy));

        // Check if call succeeded and returned 1 (valid signature)
        available = success && result.length == 32 && uint256(bytes32(result)) == 1;

        // Cache the result
        status = available ? 1 : 2;
        assembly {
            sstore(slot, status)
        }

        emit P256PrecompileDetected(available);
    }

    /// @notice Check precompile availability without caching (view function)
    /// @return available True if precompile appears available
    function isPrecompileAvailableView() internal view returns (bool available) {
        // Check cached status
        uint256 status;
        bytes32 slot = PRECOMPILE_STATUS_SLOT;
        assembly {
            status := sload(slot)
        }

        if (status == 1) return true;
        if (status == 2) return false;

        // If not cached, assume available on Osaka-compatible chains
        // Real detection requires a state-changing call
        return false;
    }

    // ============== Verification ==============
    //
    // NOTE: for "verify with automatic native-precompile + fallback" semantics,
    // import and call `solady/utils/P256.sol`'s `verifySignature` directly — it
    // already implements that exact precompile-then-fallback path, so re-wrapping
    // it here would just re-run the same probe and range checks a second time.
    // This library's value-add is the utilities below (cached availability
    // check, curve/range validation, raw-bytes verify) that Solady's P256
    // does not expose.

    /// @notice Verify with raw bytes input (160 bytes expected)
    /// @param input Packed input: hash || r || s || qx || qy
    /// @return valid True if valid
    function verifyRaw(bytes memory input) internal view returns (bool valid) {
        if (input.length != 160) revert InvalidSignatureLength();

        (bool success, bytes memory result) = P256_VERIFY.staticcall(input);

        if (!success || result.length != 32) return false;
        return uint256(bytes32(result)) == 1;
    }

    // ============== Utility Functions ==============

    /// @notice Check if public key is on the secp256r1 curve
    /// @param qx Public key x coordinate
    /// @param qy Public key y coordinate
    /// @return onCurve True if point is on curve
    function isOnCurve(bytes32 qx, bytes32 qy) internal pure returns (bool onCurve) {
        uint256 x = uint256(qx);
        uint256 y = uint256(qy);

        if (x >= P || y >= P) return false;
        if (x == 0 && y == 0) return false; // Point at infinity

        // Check y² ≡ x³ + ax + b (mod p)
        uint256 lhs = mulmod(y, y, P);
        uint256 rhs = addmod(
            addmod(
                mulmod(mulmod(x, x, P), x, P), // x³
                mulmod(A, x, P), // ax
                P
            ),
            B,
            P
        );

        return lhs == rhs;
    }

    /// @notice Validate signature components are in valid range
    /// @param r Signature r component
    /// @param s Signature s component
    /// @return valid True if r and s are in valid range (0, n)
    function isValidSignatureRange(bytes32 r, bytes32 s) internal pure returns (bool valid) {
        uint256 rVal = uint256(r);
        uint256 sVal = uint256(s);

        return rVal > 0 && rVal < N && sVal > 0 && sVal < N;
    }

    /// @notice Get precompile address
    /// @return addr The P256VERIFY precompile address (0x100)
    function precompileAddress() internal pure returns (address addr) {
        return P256_VERIFY;
    }

    /// @notice Get curve parameters
    /// @return n Curve order
    /// @return p Field modulus
    function curveParams() internal pure returns (uint256 n, uint256 p) {
        return (N, P);
    }
}
