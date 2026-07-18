// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title BlockHashLib — EIP-2935 Historical Block Hash Queries
/// @notice Queries historical block hashes from the EIP-2935 system contract.
///         Extends the EVM's native BLOCKHASH limit (256 blocks) to 8191 blocks,
///         enabling historical state verification for MEV settlement and intent validation.
/// @dev EIP-2935 stores block hashes in a ring buffer at the system contract.
///      The system contract is deployed at a deterministic address and populated
///      by the protocol at the start of each block.
///
/// @custom:eip EIP-2935: Serve historical block hashes from state
/// @custom:address 0x0000F90827F1C53a10cb7A02335B175320002935
library BlockHashLib {
    /// @dev EIP-2935 system contract address (deterministic across all chains)
    address internal constant HISTORY_CONTRACT = 0x0000F90827F1C53a10cb7A02335B175320002935;

    /// @dev Maximum number of historical blocks stored (ring buffer size)
    uint256 internal constant HISTORY_BUFFER_LENGTH = 8191;

    error BlockTooOld(uint256 requested, uint256 oldest);
    error BlockInFuture(uint256 requested, uint256 current);
    error BlockHashNotAvailable(uint256 blockNumber);

    /// @notice Get the hash of a historical block via EIP-2935 system contract
    /// @dev Falls back to native BLOCKHASH for blocks within the 256-block window.
    ///      For blocks in the 257-8191 range, queries the system contract.
    /// @param blockNumber The block number to look up
    /// @return blockHash The block hash (bytes32(0) if unavailable)
    function getBlockHash(uint256 blockNumber) internal view returns (bytes32 blockHash) {
        // Validate range
        if (blockNumber >= block.number) revert BlockInFuture(blockNumber, block.number);

        uint256 age = block.number - blockNumber;

        // Use native BLOCKHASH for recent blocks (cheaper, always available)
        if (age <= 256) {
            blockHash = blockhash(blockNumber);
            return blockHash;
        }

        // Use EIP-2935 system contract for extended history
        if (age > HISTORY_BUFFER_LENGTH) {
            revert BlockTooOld(blockNumber, block.number - HISTORY_BUFFER_LENGTH);
        }

        // Query the system contract: get(blockNumber) → bytes32
        assembly ("memory-safe") {
            // Fail closed if the system contract is not deployed; an EOA "success" would
            // otherwise return stale memory.
            if iszero(extcodesize(HISTORY_CONTRACT)) {
                mstore(0x00, shl(224, 0x3dc742b7)) // BlockHashNotAvailable(uint256)
                mstore(0x04, blockNumber)
                revert(0x00, 0x24)
            }
            let ptr := mload(0x40)
            mstore(ptr, blockNumber)
            let success := staticcall(gas(), HISTORY_CONTRACT, ptr, 0x20, ptr, 0x20)
            if iszero(success) {
                // Store BlockHashNotAvailable error
                mstore(0x00, shl(224, 0x3dc742b7)) // BlockHashNotAvailable(uint256)
                mstore(0x04, blockNumber)
                revert(0x00, 0x24)
            }
            if lt(returndatasize(), 0x20) {
                mstore(0x00, shl(224, 0x3dc742b7)) // BlockHashNotAvailable(uint256)
                mstore(0x04, blockNumber)
                revert(0x00, 0x24)
            }
            blockHash := mload(ptr)
        }
    }

    /// @notice Check if EIP-2935 system contract is available
    /// @return available True if the system contract has code deployed
    function isAvailable() internal view returns (bool available) {
        assembly ("memory-safe") {
            available := gt(extcodesize(HISTORY_CONTRACT), 0)
        }
    }

    /// @notice Get block hash with fallback — never reverts
    /// @dev Returns bytes32(0) if the block hash is not available
    /// @param blockNumber The block number to look up
    /// @return blockHash The block hash or bytes32(0)
    function getBlockHashSafe(uint256 blockNumber) internal view returns (bytes32 blockHash) {
        if (blockNumber >= block.number) return bytes32(0);

        uint256 age = block.number - blockNumber;

        if (age <= 256) {
            return blockhash(blockNumber);
        }

        if (age > HISTORY_BUFFER_LENGTH) return bytes32(0);
        if (!isAvailable()) return bytes32(0);

        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, blockNumber)
            let success := staticcall(gas(), HISTORY_CONTRACT, ptr, 0x20, ptr, 0x20)
            if success {
                if iszero(lt(returndatasize(), 0x20)) { blockHash := mload(ptr) }
            }
        }
    }

    /// @notice Verify that a specific block had a known hash
    /// @dev Used for intent settlement validation — proves a block existed with a given state
    /// @param blockNumber The block number to verify
    /// @param expectedHash The expected block hash
    /// @return valid True if the block hash matches
    function verifyBlockHash(uint256 blockNumber, bytes32 expectedHash) internal view returns (bool valid) {
        bytes32 actual = getBlockHashSafe(blockNumber);
        return actual != bytes32(0) && actual == expectedHash;
    }
}
