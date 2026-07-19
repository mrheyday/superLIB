// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title ASN1SMTCodec — ASN.1/DER wire-format mapping + SMT-LIB2 constraint strings
/// @notice Maps EVM data structures to ASN.1 DER (for interop with TLS/X.509 and similar
///         off-chain verification systems) and generates SMT-LIB2 assertion strings for
///         off-chain formal verification / symbolic execution of MEV strategies.
/// @dev Extracted from BytecodeAnalyzer: unrelated off-chain-interop concern, kept
///      separate from on-chain bytecode/ABI introspection.
library ASN1SMTCodec {
    // ========================================================================
    // Types
    // ========================================================================

    /// ASN.1 TLV (Tag-Length-Value) for wire format mapping
    struct ASN1TLV {
        uint8 tag;          // ASN.1 tag number
        uint8 tagClass;     // 0=universal, 1=application, 2=context, 3=private
        bool isConstructed; // Constructed vs primitive
        uint256 length;
        bytes value;
    }

    // ========================================================================
    // State (constants) — ASN.1 Universal Tags
    // ========================================================================
    uint8 internal constant ASN1_BOOLEAN          = 0x01;
    uint8 internal constant ASN1_INTEGER          = 0x02;
    uint8 internal constant ASN1_BIT_STRING       = 0x03;
    uint8 internal constant ASN1_OCTET_STRING     = 0x04;
    uint8 internal constant ASN1_NULL             = 0x05;
    uint8 internal constant ASN1_OID              = 0x06;
    uint8 internal constant ASN1_UTF8_STRING      = 0x0C;
    uint8 internal constant ASN1_SEQUENCE         = 0x30;
    uint8 internal constant ASN1_SET              = 0x31;

    // ========================================================================
    // Errors
    // ========================================================================
    error MalformedABIData();

    // ========================================================================
    // ASN.1 / DER Wire Format Mapping
    // ========================================================================
    // Maps EVM data structures ↔ ASN.1 DER for interop with TLS, X.509, etc.
    // Useful for bridging MEV proofs to off-chain verification systems.

    /// @notice Encode a uint256 as ASN.1 DER INTEGER
    /// @param value The uint256 to encode
    /// @return der DER-encoded integer bytes
    function encodeASN1Integer(uint256 value) internal pure returns (bytes memory der) {
        // Determine minimal encoding length
        bytes memory raw;
        if (value == 0) {
            raw = new bytes(1);
            raw[0] = 0x00;
        } else {
            // Find highest non-zero byte
            uint256 len;
            uint256 temp = value;
            while (temp > 0) {
                len++;
                temp >>= 8;
            }
            // Add leading zero if high bit set (ASN.1 integers are signed)
            bool needsPad = (value >> ((len - 1) * 8)) & 0x80 != 0;
            raw = new bytes(needsPad ? len + 1 : len);
            uint256 offset = needsPad ? 1 : 0;
            for (uint256 i; i < len; i++) {
                raw[offset + len - 1 - i] = bytes1(uint8(value >> (i * 8)));
            }
        }

        // Build TLV
        der = _buildTLV(ASN1_INTEGER, raw);
    }

    /// @notice Encode an address as ASN.1 OCTET STRING (20 bytes)
    function encodeASN1Address(address addr) internal pure returns (bytes memory) {
        bytes memory raw = new bytes(20);
        assembly { mstore(add(raw, 0x20), shl(96, addr)) }
        return _buildTLV(ASN1_OCTET_STRING, raw);
    }

    /// @notice Encode bytes32 as ASN.1 OCTET STRING
    function encodeASN1Bytes32(bytes32 data) internal pure returns (bytes memory) {
        bytes memory raw = new bytes(32);
        assembly { mstore(add(raw, 0x20), data) }
        return _buildTLV(ASN1_OCTET_STRING, raw);
    }

    /// @notice Encode a sequence of DER elements as ASN.1 SEQUENCE
    function encodeASN1Sequence(bytes memory contents) internal pure returns (bytes memory) {
        return _buildTLV(ASN1_SEQUENCE, contents);
    }

    /// @notice Decode an ASN.1 TLV from raw bytes
    function decodeASN1TLV(
        bytes memory data,
        uint256 offset
    ) internal pure returns (ASN1TLV memory tlv, uint256 nextOffset) {
        if (offset >= data.length) revert MalformedABIData();

        uint8 tagByte;
        assembly { tagByte := byte(0, mload(add(add(data, 0x20), offset))) }

        tlv.tagClass = tagByte >> 6;
        tlv.isConstructed = (tagByte & 0x20) != 0;
        tlv.tag = tagByte & 0x1F;

        offset++;

        // Decode length
        uint8 lenByte;
        assembly { lenByte := byte(0, mload(add(add(data, 0x20), offset))) }
        offset++;

        if (lenByte < 0x80) {
            tlv.length = lenByte;
        } else {
            uint8 numLenBytes = lenByte & 0x7F;
            for (uint256 i; i < numLenBytes; i++) {
                uint8 b;
                assembly { b := byte(0, mload(add(add(data, 0x20), add(offset, i)))) }
                tlv.length = (tlv.length << 8) | b;
            }
            offset += numLenBytes;
        }

        // Extract value
        tlv.value = new bytes(tlv.length);
        for (uint256 i; i < tlv.length; i++) {
            tlv.value[i] = data[offset + i];
        }
        nextOffset = offset + tlv.length;
    }

    /// @notice Map ABI-encoded data → ASN.1 SEQUENCE (for MEV proof interop)
    /// @dev Encodes: SEQUENCE { INTEGER(chainId), OCTET STRING(target), INTEGER(value), OCTET STRING(calldata) }
    function abiToASN1Proof(
        uint256 chainId,
        address target,
        uint256 value,
        bytes memory data
    ) internal pure returns (bytes memory) {
        bytes memory contents = abi.encodePacked(
            encodeASN1Integer(chainId),
            encodeASN1Address(target),
            encodeASN1Integer(value),
            _buildTLV(ASN1_OCTET_STRING, data)
        );
        return encodeASN1Sequence(contents);
    }

    // ========================================================================
    // SMT (Satisfiability Modulo Theories) Constraint Map
    // ========================================================================
    // Encodes EVM execution constraints as SMT-LIB2 assertions for off-chain
    // formal verification / symbolic execution of MEV strategies.

    /// @notice Generate an SMT assertion string for a profit constraint
    /// @param minProfit Minimum profit in wei
    /// @param gasPrice Gas price in wei
    /// @param gasLimit Gas limit
    /// @return assertion SMT-LIB2 assertion string
    function smtProfitConstraint(
        uint256 minProfit,
        uint256 gasPrice,
        uint256 gasLimit
    ) internal pure returns (string memory assertion) {
        // (assert (>= (- amountOut amountIn) (+ minProfit (* gasPrice gasLimit))))
        assertion = string(abi.encodePacked(
            "(assert (>= (- amountOut amountIn) (+ ",
            _uint256ToDecimal(minProfit),
            " (* ",
            _uint256ToDecimal(gasPrice),
            " ",
            _uint256ToDecimal(gasLimit),
            "))))"
        ));
    }

    /// @notice Generate SMT constraint for sandwich bounds
    function smtSandwichConstraint(
        uint256 victimAmountIn,
        uint256 maxFrontrunPct // in BPS (10000 = 100%)
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(
            "(assert (and ",
            "(> frontrunAmount 0) ",
            "(<= frontrunAmount (/ (* ",
            _uint256ToDecimal(victimAmountIn),
            " ",
            _uint256ToDecimal(maxFrontrunPct),
            ") 10000))))"
        ));
    }

    /// @notice Generate SMT constraint for arbitrage path
    function smtArbPathConstraint(
        uint256 poolCount
    ) internal pure returns (string memory) {
        // (assert (and (> amountOut_N amountIn_0) (forall ((i Int)) (=> (and (>= i 0) (< i N)) (> reserve_i 0)))))
        return string(abi.encodePacked(
            "(assert (and (> amountOut_",
            _uint256ToDecimal(poolCount),
            " amountIn_0) ",
            "(forall ((i Int)) (=> (and (>= i 0) (< i ",
            _uint256ToDecimal(poolCount),
            ")) (> reserve_i 0)))))"
        ));
    }

    // ========================================================================
    // Internal Helpers
    // ========================================================================

    /// @dev Build ASN.1 TLV (Tag-Length-Value)
    function _buildTLV(uint8 tag, bytes memory value) private pure returns (bytes memory) {
        uint256 len = value.length;
        bytes memory lenBytes;

        if (len < 0x80) {
            lenBytes = new bytes(1);
            lenBytes[0] = bytes1(uint8(len));
        } else if (len < 0x100) {
            lenBytes = new bytes(2);
            lenBytes[0] = 0x81;
            lenBytes[1] = bytes1(uint8(len));
        } else if (len < 0x10000) {
            lenBytes = new bytes(3);
            lenBytes[0] = 0x82;
            lenBytes[1] = bytes1(uint8(len >> 8));
            lenBytes[2] = bytes1(uint8(len));
        } else if (len < 0x1000000) {
            lenBytes = new bytes(4);
            lenBytes[0] = 0x83;
            lenBytes[1] = bytes1(uint8(len >> 16));
            lenBytes[2] = bytes1(uint8(len >> 8));
            lenBytes[3] = bytes1(uint8(len));
        } else {
            lenBytes = new bytes(5);
            lenBytes[0] = 0x84;
            lenBytes[1] = bytes1(uint8(len >> 24));
            lenBytes[2] = bytes1(uint8(len >> 16));
            lenBytes[3] = bytes1(uint8(len >> 8));
            lenBytes[4] = bytes1(uint8(len));
        }

        return abi.encodePacked(tag, lenBytes, value);
    }

    /// @dev Convert uint256 to decimal string
    function _uint256ToDecimal(uint256 value) private pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
