// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title BytecodeAnalyzer — On-chain bytecode introspection, opcode map & ABI codec
/// @notice Provides runtime bytecode analysis, EVM opcode mapping, ABI encode/decode
///         maps for MEV execution validation. Used by Rust orchestration to verify
///         contract bytecode before interacting, decode return data, and build calldata.
/// @dev All assembly uses Osaka-native opcodes (MCOPY, TSTORE/TLOAD where beneficial).
library BytecodeAnalyzer {
    // ========================================================================
    // Errors
    // ========================================================================
    error EmptyBytecode();
    error InvalidJumpDest();
    error MalformedABIData();
    error SelectorNotFound(bytes4 selector);

    // ========================================================================
    // Events
    // ========================================================================
    event BytecodeAnalyzed(address indexed target, uint256 codeSize, uint256 opcodeCount);
    event SelectorExtracted(address indexed target, bytes4 selector);
    event ABIDecoded(bytes4 selector, uint256 paramCount);

    // ========================================================================
    // Constants — EVM Opcode Map (Osaka / Cancun+CLZ superset)
    // ========================================================================

    // Stack ops
    uint8 internal constant OP_STOP       = 0x00;
    uint8 internal constant OP_ADD        = 0x01;
    uint8 internal constant OP_MUL       = 0x02;
    uint8 internal constant OP_SUB        = 0x03;
    uint8 internal constant OP_DIV        = 0x04;
    uint8 internal constant OP_SDIV       = 0x05;
    uint8 internal constant OP_MOD        = 0x06;
    uint8 internal constant OP_SMOD       = 0x07;
    uint8 internal constant OP_ADDMOD     = 0x08;
    uint8 internal constant OP_MULMOD     = 0x09;
    uint8 internal constant OP_EXP        = 0x0A;
    uint8 internal constant OP_SIGNEXTEND = 0x0B;

    // Comparison & bitwise
    uint8 internal constant OP_LT     = 0x10;
    uint8 internal constant OP_GT     = 0x11;
    uint8 internal constant OP_SLT    = 0x12;
    uint8 internal constant OP_SGT    = 0x13;
    uint8 internal constant OP_EQ     = 0x14;
    uint8 internal constant OP_ISZERO = 0x15;
    uint8 internal constant OP_AND    = 0x16;
    uint8 internal constant OP_OR     = 0x17;
    uint8 internal constant OP_XOR    = 0x18;
    uint8 internal constant OP_NOT    = 0x19;
    uint8 internal constant OP_BYTE   = 0x1A;
    uint8 internal constant OP_SHL    = 0x1B;
    uint8 internal constant OP_SHR    = 0x1C;
    uint8 internal constant OP_SAR    = 0x1D;
    uint8 internal constant OP_CLZ    = 0x1E;

    // Keccak256
    uint8 internal constant OP_KECCAK256 = 0x20;

    // Environmental
    uint8 internal constant OP_ADDRESS      = 0x30;
    uint8 internal constant OP_BALANCE      = 0x31;
    uint8 internal constant OP_ORIGIN       = 0x32;
    uint8 internal constant OP_CALLER       = 0x33;
    uint8 internal constant OP_CALLVALUE    = 0x34;
    uint8 internal constant OP_CALLDATALOAD = 0x35;
    uint8 internal constant OP_CALLDATASIZE = 0x36;
    uint8 internal constant OP_CALLDATACOPY = 0x37;
    uint8 internal constant OP_CODESIZE     = 0x38;
    uint8 internal constant OP_CODECOPY     = 0x39;
    uint8 internal constant OP_GASPRICE     = 0x3A;
    uint8 internal constant OP_EXTCODESIZE  = 0x3B;
    uint8 internal constant OP_EXTCODECOPY  = 0x3C;
    uint8 internal constant OP_RETURNDATASIZE = 0x3D;
    uint8 internal constant OP_RETURNDATACOPY = 0x3E;
    uint8 internal constant OP_EXTCODEHASH  = 0x3F;

    // Block
    uint8 internal constant OP_BLOCKHASH  = 0x40;
    uint8 internal constant OP_COINBASE   = 0x41;
    uint8 internal constant OP_TIMESTAMP  = 0x42;
    uint8 internal constant OP_NUMBER     = 0x43;
    uint8 internal constant OP_PREVRANDAO = 0x44;
    uint8 internal constant OP_GASLIMIT   = 0x45;
    uint8 internal constant OP_CHAINID    = 0x46;
    uint8 internal constant OP_SELFBALANCE = 0x47;
    uint8 internal constant OP_BASEFEE    = 0x48;
    uint8 internal constant OP_BLOBHASH   = 0x49;  // EIP-4844
    uint8 internal constant OP_BLOBBASEFEE = 0x4A;  // EIP-7516

    // Memory / Storage
    uint8 internal constant OP_POP      = 0x50;
    uint8 internal constant OP_MLOAD    = 0x51;
    uint8 internal constant OP_MSTORE   = 0x52;
    uint8 internal constant OP_MSTORE8  = 0x53;
    uint8 internal constant OP_SLOAD    = 0x54;
    uint8 internal constant OP_SSTORE   = 0x55;
    uint8 internal constant OP_JUMP     = 0x56;
    uint8 internal constant OP_JUMPI    = 0x57;
    uint8 internal constant OP_PC       = 0x58;
    uint8 internal constant OP_MSIZE    = 0x59;
    uint8 internal constant OP_GAS      = 0x5A;
    uint8 internal constant OP_JUMPDEST = 0x5B;

    // EIP-1153: Transient storage (Cancun)
    uint8 internal constant OP_TLOAD  = 0x5C;
    uint8 internal constant OP_TSTORE = 0x5D;

    // EIP-5656: MCOPY (Cancun)
    uint8 internal constant OP_MCOPY = 0x5E;

    // PUSHn
    uint8 internal constant OP_PUSH0  = 0x5F;
    uint8 internal constant OP_PUSH1  = 0x60;
    uint8 internal constant OP_PUSH32 = 0x7F;

    // DUPn / SWAPn
    uint8 internal constant OP_DUP1  = 0x80;
    uint8 internal constant OP_DUP16 = 0x8F;
    uint8 internal constant OP_SWAP1  = 0x90;
    uint8 internal constant OP_SWAP16 = 0x9F;

    // LOGn
    uint8 internal constant OP_LOG0 = 0xA0;
    uint8 internal constant OP_LOG4 = 0xA4;

    // System
    uint8 internal constant OP_CREATE       = 0xF0;
    uint8 internal constant OP_CALL         = 0xF1;
    uint8 internal constant OP_CALLCODE     = 0xF2;
    uint8 internal constant OP_RETURN       = 0xF3;
    uint8 internal constant OP_DELEGATECALL = 0xF4;
    uint8 internal constant OP_CREATE2      = 0xF5;
    uint8 internal constant OP_STATICCALL   = 0xFA;
    uint8 internal constant OP_REVERT       = 0xFD;
    uint8 internal constant OP_INVALID      = 0xFE;
    uint8 internal constant OP_SELFDESTRUCT = 0xFF;

    // ========================================================================
    // Structs
    // ========================================================================

    /// Bytecode analysis result
    struct BytecodeProfile {
        uint256 codeSize;
        uint256 opcodeCount;
        uint256 pushCount;
        uint256 jumpDestCount;
        uint256 externalCallCount;  // CALL + STATICCALL + DELEGATECALL
        uint256 storageAccessCount; // SLOAD + SSTORE + TLOAD + TSTORE
        bool hasSelfDestruct;
        bool hasCreate;
        bool hasDelegateCall;
        bytes4[] selectors;         // Function selectors found in bytecode
    }

    /// ABI Type descriptor — maps Solidity types to ABI encoding rules
    struct ABITypeDescriptor {
        uint8 typeId;       // 0=uint, 1=int, 2=address, 3=bool, 4=bytes, 5=string, 6=array, 7=tuple
        uint16 bitWidth;    // For uint/int: 8..256; for bytesN: 8..256
        bool isDynamic;     // Requires offset indirection
        bool isArray;       // Dynamic-length array
        uint256 arrayLen;   // Fixed array length (0 = dynamic)
    }

    // ========================================================================
    // Core: Bytecode Analysis
    // ========================================================================

    /// @notice Analyze runtime bytecode of a deployed contract
    /// @param target The contract address to analyze
    /// @return profile Complete bytecode analysis profile
    function analyzeBytecode(address target) internal view returns (BytecodeProfile memory profile) {
        uint256 size;
        assembly { size := extcodesize(target) }
        if (size == 0) revert EmptyBytecode();

        bytes memory code = new bytes(size);
        assembly { extcodecopy(target, add(code, 0x20), 0, size) }

        profile.codeSize = size;

        // Temporary selector storage (max 256 selectors)
        bytes4[] memory tempSelectors = new bytes4[](256);
        uint256 selectorCount;

        uint256 i;
        while (i < size) {
            uint8 op;
            assembly { op := byte(0, mload(add(add(code, 0x20), i))) }

            profile.opcodeCount++;

            // Detect PUSH4 followed by EQ (selector matching pattern)
            if (op == 0x63 && i + 5 < size) { // PUSH4
                bytes4 sel;
                assembly {
                    sel := mload(add(add(code, 0x21), i))
                }
                // Check if followed by common selector check pattern
                if (i + 5 < size) {
                    uint8 nextOp;
                    assembly { nextOp := byte(0, mload(add(add(code, 0x20), add(i, 5)))) }
                    if (nextOp == OP_EQ && selectorCount < 256) {
                        tempSelectors[selectorCount++] = sel;
                    }
                }
            }

            // Count categories
            if (op >= OP_PUSH0 && op <= OP_PUSH32) {
                profile.pushCount++;
                // Skip push data bytes
                if (op > OP_PUSH0) {
                    i += (op - OP_PUSH0);
                }
            } else if (op == OP_JUMPDEST) {
                profile.jumpDestCount++;
            } else if (op == OP_CALL || op == OP_STATICCALL || op == OP_DELEGATECALL) {
                profile.externalCallCount++;
                if (op == OP_DELEGATECALL) profile.hasDelegateCall = true;
            } else if (op == OP_SLOAD || op == OP_SSTORE || op == OP_TLOAD || op == OP_TSTORE) {
                profile.storageAccessCount++;
            } else if (op == OP_CREATE || op == OP_CREATE2) {
                profile.hasCreate = true;
            } else if (op == OP_SELFDESTRUCT) {
                profile.hasSelfDestruct = true;
            }

            i++;
        }

        // Copy selectors to properly-sized array
        profile.selectors = new bytes4[](selectorCount);
        for (uint256 j; j < selectorCount; j++) {
            profile.selectors[j] = tempSelectors[j];
        }
    }

    /// @notice Get raw bytecode of a contract
    function getCode(address target) internal view returns (bytes memory code) {
        uint256 size;
        assembly { size := extcodesize(target) }
        if (size == 0) revert EmptyBytecode();
        code = new bytes(size);
        assembly { extcodecopy(target, add(code, 0x20), 0, size) }
    }

    /// @notice Check if a specific opcode exists in bytecode
    function containsOpcode(address target, uint8 opcode) internal view returns (bool found) {
        bytes memory code = getCode(target);
        uint256 size = code.length;
        uint256 i;
        while (i < size) {
            uint8 op;
            assembly { op := byte(0, mload(add(add(code, 0x20), i))) }
            if (op == opcode) return true;
            // Skip PUSH data
            if (op >= OP_PUSH1 && op <= OP_PUSH32) {
                i += (op - OP_PUSH0);
            }
            i++;
        }
        return false;
    }

    // ========================================================================
    // ABI Encode / Decode Map
    // ========================================================================

    /// @notice Encode a function call with type-safe packing
    /// @param selector The 4-byte function selector
    /// @param params ABI-encoded parameters (packed after selector)
    /// @return calldata The complete ABI-encoded calldata
    function encodeCall(
        bytes4 selector,
        bytes memory params
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(selector, params);
    }

    /// @notice Decode function selector from calldata
    function decodeSelector(bytes calldata data) internal pure returns (bytes4 selector) {
        if (data.length < 4) revert MalformedABIData();
        selector = bytes4(data[:4]);
    }

    /// @notice Decode a single uint256 parameter at a given offset
    function decodeUint256(
        bytes calldata data,
        uint256 offset
    ) internal pure returns (uint256 value) {
        if (data.length < offset + 32) revert MalformedABIData();
        assembly {
            value := calldataload(add(data.offset, offset))
        }
    }

    /// @notice Decode an address parameter at a given offset (ABI-encoded, right-aligned)
    function decodeAddress(
        bytes calldata data,
        uint256 offset
    ) internal pure returns (address value) {
        if (data.length < offset + 32) revert MalformedABIData();
        assembly {
            value := and(calldataload(add(data.offset, offset)), 0xffffffffffffffffffffffffffffffffffffffff)
        }
    }

    /// @notice Decode multiple uint256 values from ABI-encoded return data
    function decodeUint256Array(
        bytes memory data,
        uint256 count
    ) internal pure returns (uint256[] memory values) {
        if (data.length < count * 32) revert MalformedABIData();
        values = new uint256[](count);
        for (uint256 i; i < count; i++) {
            assembly {
                mstore(
                    add(add(values, 0x20), mul(i, 0x20)),
                    mload(add(add(data, 0x20), mul(i, 0x20)))
                )
            }
        }
    }

    /// @notice Build the complete ABI type map for a function signature
    /// @param sig The function signature string (e.g., "swap(address,uint256,uint256,bytes)")
    /// @return typeCount Number of parameter types
    /// @return hasDynamic Whether any parameter is dynamically encoded
    function analyzeSignature(
        string memory sig
    ) internal pure returns (uint256 typeCount, bool hasDynamic) {
        bytes memory b = bytes(sig);
        bool inParens;
        uint256 depth;

        for (uint256 i; i < b.length; i++) {
            if (b[i] == "(") {
                if (!inParens) {
                    inParens = true;
                    depth = 1;
                } else {
                    depth++;
                }
            } else if (b[i] == ")") {
                depth--;
                if (depth == 0) break;
            } else if (b[i] == "," && depth == 1) {
                typeCount++;
            } else if (inParens && depth == 1) {
                // Check for dynamic types
                if (b[i] == "b" && i + 4 < b.length) {
                    // "bytes" (not bytes32 etc.) or "bytes[]"
                    if (b[i + 1] == "y" && b[i + 2] == "t" && b[i + 3] == "e" && b[i + 4] == "s") {
                        if (i + 5 >= b.length || b[i + 5] == "," || b[i + 5] == ")" || b[i + 5] == "[") {
                            hasDynamic = true;
                        }
                    }
                } else if (b[i] == "s" && i + 5 < b.length) {
                    // "string"
                    if (b[i + 1] == "t" && b[i + 2] == "r" && b[i + 3] == "i" && b[i + 4] == "n" && b[i + 5] == "g") {
                        hasDynamic = true;
                    }
                } else if (b[i] == "[" && i + 1 < b.length && b[i + 1] == "]") {
                    hasDynamic = true;
                }
            }
        }
        // Only count the last param if there was at least one char between parens
        if (inParens && typeCount > 0) {
            typeCount++; // Last parameter (after final comma)
        } else if (inParens) {
            // Check if there was any content between the parens
            // typeCount == 0 and no comma means either 0 or 1 param
            // We need to check if the parens were empty
            bytes memory raw = bytes(sig);
            for (uint256 j; j < raw.length; j++) {
                if (raw[j] == "(") {
                    if (j + 1 < raw.length && raw[j + 1] != ")") {
                        typeCount = 1; // Single param, no commas
                    }
                    break;
                }
            }
        }
    }

    /// @notice Compute the function selector from a signature string
    function computeSelector(string memory sig) internal pure returns (bytes4) {
        return bytes4(keccak256(bytes(sig)));
    }
}
