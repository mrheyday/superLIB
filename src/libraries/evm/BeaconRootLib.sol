// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title BeaconRootLib — EIP-4788 Beacon Block Root Access
/// @notice Provides trustless access to beacon chain block roots from the EVM.
///         Enables consensus-layer state verification for MEV applications including:
///           - Proposer identity verification (pre-confirmation protocols)
///           - Validator balance proofs (liquidation anchoring)
///           - Beacon state root proofs (cross-domain settlement)
///           - Trustless TWAP anchoring against consensus timestamps
///
/// @dev EIP-4788 (Live since Dencun / Cancun-Deneb, May 2024):
///      The beacon block root is stored in a ring buffer at the system contract.
///      The contract is populated by the system at the start of each block with
///      the parent beacon block root.
///
///      Ring buffer layout (at system contract 0x000F3df6D732807Ef1319fB7B8bB8522d0Beac02):
///        - Slots 0..8190: timestamps (keyed by timestamp % 8191)
///        - Slots 8191..16381: beacon roots (keyed by timestamp % 8191 + 8191)
///      Query: send 32-byte big-endian timestamp as calldata → returns 32-byte beacon root
///      Reverts if timestamp not found in the ring buffer.
///
///      Buffer covers ~27.3 hours of slots (8191 × 12s = 98,292s).
///
/// @custom:eip EIP-4788: Beacon block root in the EVM
/// @custom:address 0x000F3df6D732807Ef1319fB7B8bB8522d0Beac02
/// @custom:status LIVE — Dencun fork (all EVM chains with beacon chain)
library BeaconRootLib {
    /// @dev EIP-4788 system contract address (deterministic across all chains)
    address internal constant BEACON_ROOTS_CONTRACT = 0x000F3df6D732807Ef1319fB7B8bB8522d0Beac02;

    /// @dev Ring buffer size: 8191 slots (~27.3 hours at 12s/slot)
    uint256 internal constant HISTORY_BUFFER_LENGTH = 8191;

    /// @dev Seconds per beacon chain slot
    uint256 internal constant SECONDS_PER_SLOT = 12;

    // ═══════════════════════════════════════════════════════════════
    //                         ERRORS
    // ═══════════════════════════════════════════════════════════════

    /// @dev Beacon root not available for the requested timestamp
    error BeaconRootNotAvailable(uint256 queryTimestamp);

    /// @dev Timestamp is in the future
    error TimestampInFuture(uint256 requested, uint256 current);

    /// @dev Timestamp is too old (outside ring buffer window)
    error TimestampTooOld(uint256 requested, uint256 oldestAvailable);

    /// @dev Beacon roots system contract not deployed on this chain
    error BeaconRootsNotDeployed();

    // ═══════════════════════════════════════════════════════════════
    //                    CORE QUERIES
    // ═══════════════════════════════════════════════════════════════

    /// @notice Get the beacon block root for a given timestamp
    /// @dev Calls the EIP-4788 system contract with the timestamp as calldata.
    ///      The system contract verifies the timestamp exists in its ring buffer
    ///      and returns the corresponding beacon block root.
    /// @param queryTimestamp The timestamp to query (must be within the ring buffer window)
    /// @return root The beacon block root at the given timestamp
    function getBeaconRoot(uint256 queryTimestamp) internal view returns (bytes32 root) {
        assembly ("memory-safe") {
            // Fail closed if the system contract is not deployed (EOA "success" would otherwise
            // return stale memory, enabling bypasses in any enforcement path).
            if iszero(extcodesize(BEACON_ROOTS_CONTRACT)) {
                mstore(0x00, 0x2166950b) // BeaconRootsNotDeployed()
                revert(0x1c, 0x04)
            }

            // Validate: not in the future
            if gt(queryTimestamp, timestamp()) {
                mstore(0x00, shl(224, 0x45e2dc22)) // TimestampInFuture(uint256,uint256)
                mstore(0x04, queryTimestamp)
                mstore(0x24, timestamp())
                revert(0x00, 0x44)
            }

            // Call system contract: send 32-byte timestamp → receive 32-byte root
            let ptr := mload(0x40)
            mstore(ptr, queryTimestamp)
            let success := staticcall(gas(), BEACON_ROOTS_CONTRACT, ptr, 0x20, ptr, 0x20)

            if iszero(success) {
                // BeaconRootNotAvailable(uint256)
                mstore(0x00, shl(224, 0x3c970f2c)) // BeaconRootNotAvailable(uint256)
                mstore(0x04, queryTimestamp)
                revert(0x00, 0x24)
            }
            // A "successful" call to an address with no code returns empty data.
            // Require a full 32-byte root to avoid reading stale memory.
            if lt(returndatasize(), 0x20) {
                mstore(0x00, 0x2166950b) // BeaconRootsNotDeployed()
                revert(0x1c, 0x04)
            }

            root := mload(ptr)
        }
    }

    /// @notice Get the beacon block root — safe variant that never reverts
    /// @dev Returns bytes32(0) if the root is not available for any reason
    /// @param queryTimestamp The timestamp to query
    /// @return root The beacon block root or bytes32(0)
    function getBeaconRootSafe(uint256 queryTimestamp) internal view returns (bytes32 root) {
        if (queryTimestamp > block.timestamp) return bytes32(0);
        if (!isAvailable()) return bytes32(0);

        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, queryTimestamp)
            let success := staticcall(gas(), BEACON_ROOTS_CONTRACT, ptr, 0x20, ptr, 0x20)
            if success {
                if iszero(lt(returndatasize(), 0x20)) { root := mload(ptr) }
            }
        }
    }

    /// @notice Get the parent beacon block root (most recent available)
    /// @dev The system contract stores the parent beacon root at the start of each block,
    ///      so `block.timestamp` should always have the parent root available.
    /// @return root The parent beacon block root
    function getParentBeaconRoot() internal view returns (bytes32 root) {
        return getBeaconRootSafe(block.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════
    //                    VERIFICATION
    // ═══════════════════════════════════════════════════════════════

    /// @notice Verify that a specific timestamp had a known beacon root
    /// @dev Used for trustless consensus state verification — proves a beacon block
    ///      existed with a given root at a given timestamp.
    /// @param queryTimestamp The timestamp to verify
    /// @param expectedRoot The expected beacon block root
    /// @return valid True if the beacon root matches
    function verifyBeaconRoot(uint256 queryTimestamp, bytes32 expectedRoot) internal view returns (bool valid) {
        bytes32 actual = getBeaconRootSafe(queryTimestamp);
        return actual != bytes32(0) && actual == expectedRoot;
    }

    // ═══════════════════════════════════════════════════════════════
    //                    AVAILABILITY
    // ═══════════════════════════════════════════════════════════════

    /// @notice Check if the EIP-4788 beacon roots system contract is deployed
    /// @return available True if the system contract has code
    function isAvailable() internal view returns (bool available) {
        assembly ("memory-safe") {
            available := gt(extcodesize(BEACON_ROOTS_CONTRACT), 0)
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //                    TIMESTAMP HELPERS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Estimate the oldest timestamp available in the ring buffer
    /// @dev Approximate: current timestamp minus (8191 × 12 seconds)
    /// @return oldest Estimated oldest available timestamp
    function oldestAvailableTimestamp() internal view returns (uint256 oldest) {
        uint256 windowSize = HISTORY_BUFFER_LENGTH * SECONDS_PER_SLOT; // 98292 seconds
        if (block.timestamp > windowSize) {
            oldest = block.timestamp - windowSize;
        }
        // If block.timestamp <= windowSize, returns 0 (genesis)
    }

    /// @notice Check if a timestamp is within the beacon root ring buffer window
    /// @param queryTimestamp The timestamp to check
    /// @return inWindow True if the timestamp should be available
    function isInWindow(uint256 queryTimestamp) internal view returns (bool inWindow) {
        if (queryTimestamp > block.timestamp) return false;
        uint256 oldest = oldestAvailableTimestamp();
        return queryTimestamp >= oldest;
    }

    /// @notice Estimate the beacon slot number for a given timestamp
    /// @dev Uses Ethereum mainnet genesis time. For other networks, adjust GENESIS_TIMESTAMP.
    /// @param queryTimestamp The timestamp to convert
    /// @return slot Estimated beacon slot number
    function estimateSlot(uint256 queryTimestamp) internal pure returns (uint64 slot) {
        // Beacon chain genesis: Dec 1, 2020 12:00:23 UTC (1606824023)
        uint256 BEACON_GENESIS = 1_606_824_023;
        if (queryTimestamp <= BEACON_GENESIS) return 0;
        slot = uint64((queryTimestamp - BEACON_GENESIS) / SECONDS_PER_SLOT);
    }
}
