// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import { LibTransient } from "solady/utils/LibTransient.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";
import { LibBit } from "solady/utils/LibBit.sol";

/// @title SafetyLib
/// @notice Failsafe library using Osaka EVM transient storage (EIP-1153)
/// @dev Pure execution guards — zero logic, all decisions made off-chain by Rust
/// @custom:security Transient reentrancy guard (100 gas vs SSTORE 2100+)
/// @custom:security Circuit breaker: pause bit stored in SSTORE for persistence
/// @custom:security Deadline enforcement: all execution paths must be time-bounded
/// @custom:security Profit invariant: ETH or token balance must increase
/// @custom:eip EIP-7971/7609: Enhanced transient storage patterns (TLOAD 5 gas, TSTORE 12 gas)
/// @custom:eip EIP-7732: ePBS-aware coinbase tipping
/// @custom:eip EIP-5000: MULDIV-ready profit calculations
library SafetyLib {
    using LibTransient for LibTransient.TUint256;

    // ═══════════════════════════════════════════════════════════════
    //                    TRANSIENT STORAGE SLOTS
    // ═══════════════════════════════════════════════════════════════

    uint256 internal constant LOCK_SLOT = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400e;

    uint256 internal constant CONTEXT_SLOT = 0xa11ce00000000000000000000000000000000000000000000000000000000001;

    uint256 internal constant BALANCE_SNAPSHOT_SLOT =
        0xba1a2ce000000000000000000000000000000000000000000000000000000001;

    // ═══════════════════════════════════════════════════════════════
    //       EIP-7971/7609: PER-HOP PROFIT TRACKING SLOTS
    //       Economically viable at TLOAD=5gas / TSTORE=12gas
    // ═══════════════════════════════════════════════════════════════

    /// @dev Base slot for per-hop token balance snapshots: slot = HOP_BALANCE_BASE + hopIndex
    uint256 internal constant HOP_BALANCE_BASE = 0x480700000000000000000000000000000000000000000000000000000000000;

    /// @dev Slot storing the current hop index counter
    uint256 internal constant HOP_COUNTER_SLOT = 0x480700000000000000000000000000000000000000000000000000000000fff;

    /// @dev Base slot for per-token balance snapshots: slot = TOKEN_SNAPSHOT_BASE + uint160(token)
    uint256 internal constant TOKEN_SNAPSHOT_BASE = 0x746f6b656e736e617000000000000000000000000000000000000000000000;

    // ═══════════════════════════════════════════════════════════════
    //                    PERSISTENT STORAGE SLOTS
    // ═══════════════════════════════════════════════════════════════

    uint256 internal constant CIRCUIT_BREAKER_SLOT = 0xd4be9ff5a3d11a371f0f0d86cf2cbcc568347c23eb6fecfe6c8d855b23dbab99;

    // ═══════════════════════════════════════════════════════════════
    //                         ERRORS
    // ═══════════════════════════════════════════════════════════════

    error Reentrancy();
    error CircuitBreakerTripped();
    error DeadlineExpired();
    error NoProfitGenerated();
    error GasLimitExceeded();
    error Unauthorized();
    error TargetNotContract();

    // ═══════════════════════════════════════════════════════════════
    //                    CODELESS ADDRESS GUARD
    // ═══════════════════════════════════════════════════════════════

    function enforceHasCode(address target) internal view {
        assembly ("memory-safe") {
            if iszero(extcodesize(target)) {
                mstore(0x00, 0x0171bf56) // TargetNotContract()
                revert(0x1c, 0x04)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //                    REENTRANCY GUARD (EIP-1153)
    // ═══════════════════════════════════════════════════════════════

    function acquireLock() internal {
        assembly ("memory-safe") {
            if tload(LOCK_SLOT) {
                mstore(0x00, 0xab143c06) // Reentrancy()
                revert(0x1c, 0x04)
            }
            tstore(LOCK_SLOT, 1)
        }
    }

    function releaseLock() internal {
        assembly ("memory-safe") {
            tstore(LOCK_SLOT, 0)
        }
    }

    function isLocked() internal view returns (bool locked) {
        assembly ("memory-safe") {
            locked := tload(LOCK_SLOT)
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //                    CIRCUIT BREAKER
    // ═══════════════════════════════════════════════════════════════

    function checkCircuitBreaker() internal view {
        assembly ("memory-safe") {
            let state := sload(CIRCUIT_BREAKER_SLOT)
            if and(state, 1) {
                mstore(0x00, 0xf40982ef) // CircuitBreakerTripped()
                revert(0x1c, 0x04)
            }
        }
    }

    function tripCircuitBreaker() internal {
        assembly ("memory-safe") {
            let state := sload(CIRCUIT_BREAKER_SLOT)
            sstore(CIRCUIT_BREAKER_SLOT, or(state, 1))
        }
    }

    function resetCircuitBreaker() internal {
        assembly ("memory-safe") {
            let state := sload(CIRCUIT_BREAKER_SLOT)
            sstore(CIRCUIT_BREAKER_SLOT, and(state, shl(65, sub(shl(64, 1), 1))))
        }
    }

    /// @notice Read circuit-breaker status fields.
    /// @return tripped Whether breaker is currently tripped.
    /// @return failures Consecutive failure counter.
    /// @return totalSuccess Total successful execution counter (truncated to 64 bits for reporting).
    function circuitBreakerState() internal view returns (bool tripped, uint64 failures, uint64 totalSuccess) {
        assembly ("memory-safe") {
            let state := sload(CIRCUIT_BREAKER_SLOT)
            tripped := and(state, 1)
            failures := and(shr(1, state), sub(shl(64, 1), 1))
            totalSuccess := and(shr(65, state), sub(shl(64, 1), 1))
        }
    }

    /// @notice Convenience helper for tripped bit checks without reverting.
    function isCircuitBreakerTripped() internal view returns (bool tripped) {
        assembly ("memory-safe") {
            tripped := and(sload(CIRCUIT_BREAKER_SLOT), 1)
        }
    }

    /// @dev Records a successful execution. Clears failure count (resets consecutive
    ///      failure tracking) and increments total success count. The tripped bit (bit 0)
    ///      is NOT cleared here — only resetCircuitBreaker() can clear it.
    function recordSuccess() internal {
        assembly ("memory-safe") {
            let state := sload(CIRCUIT_BREAKER_SLOT)
            let tripped := and(state, 1)
            let total := add(shr(65, and(state, shl(65, sub(shl(64, 1), 1)))), 1)
            // Preserve tripped bit, clear failure count (bits 1-64), increment success count
            sstore(CIRCUIT_BREAKER_SLOT, or(tripped, shl(65, total)))
        }
    }

    function recordFailure(uint64 maxFailures) internal {
        assembly ("memory-safe") {
            let state := sload(CIRCUIT_BREAKER_SLOT)
            let failures := add(shr(1, and(state, shl(1, sub(shl(64, 1), 1)))), 1)
            let total := shr(65, and(state, shl(65, sub(shl(64, 1), 1))))
            let newState := or(shl(1, failures), shl(65, total))
            if gt(failures, maxFailures) { newState := or(newState, 1) }
            sstore(CIRCUIT_BREAKER_SLOT, newState)
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //                    DEADLINE ENFORCEMENT
    // ═══════════════════════════════════════════════════════════════

    function enforceDeadline(uint256 deadline) internal view {
        assembly ("memory-safe") {
            if gt(timestamp(), deadline) {
                mstore(0x00, 0x1ab7da6b) // DeadlineExpired()
                revert(0x1c, 0x04)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //                    BALANCE SNAPSHOTS
    // ═══════════════════════════════════════════════════════════════

    function snapshotBalance() internal {
        LibTransient.tUint256(BALANCE_SNAPSHOT_SLOT).set(address(this).balance);
    }

    function snapshotBalance(uint256 _bal) internal {
        LibTransient.tUint256(BALANCE_SNAPSHOT_SLOT).set(_bal);
    }

    function enforceProfitInvariant() internal view returns (uint256 profit) {
        uint256 before = LibTransient.tUint256(BALANCE_SNAPSHOT_SLOT).get();
        uint256 current = address(this).balance;
        if (current <= before) revert NoProfitGenerated();
        profit = current - before;
    }

    function checkProfit() internal view returns (bool profitable, uint256 amount) {
        uint256 before = LibTransient.tUint256(BALANCE_SNAPSHOT_SLOT).get();
        uint256 current = address(this).balance;
        amount = FixedPointMathLib.zeroFloorSub(current, before);
        profitable = amount > 0;
    }

    // ═══════════════════════════════════════════════════════════════
    //                    TOKEN BALANCE HELPERS
    // ═══════════════════════════════════════════════════════════════

    function tokenBalance(address token) internal view returns (uint256 bal) {
        assembly ("memory-safe") {
            if iszero(extcodesize(token)) {
                mstore(0x00, 0x0171bf56) // TargetNotContract()
                revert(0x1c, 0x04)
            }
            mstore(0x00, 0x70a08231)
            mstore(0x20, address())
            if iszero(staticcall(gas(), token, 0x1c, 0x24, 0x00, 0x20)) { revert(0x00, 0x00) }
            if lt(returndatasize(), 0x20) { revert(0x00, 0x00) }
            bal := mload(0x00)
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //                          COINBASE TIP
    // ═══════════════════════════════════════════════════════════════

    /// @notice Tip coinbase a share of profit.
    function tipCoinbase(uint256 profit, uint16 tipBps) internal returns (uint256 tipPaid) {
        if (tipBps == 0 || tipBps > 10_000) return 0;
        tipPaid = FixedPointMathLib.fullMulDiv(profit, tipBps, 10_000);
        if (tipPaid > 0) {
            assembly ("memory-safe") {
                if iszero(call(gas(), coinbase(), tipPaid, 0, 0, 0, 0)) {
                    tipPaid := 0
                }
            }
        }
    }

    /// @notice ePBS-aware coinbase tip (EIP-7732)
    /// @dev Under ePBS, coinbase is the in-protocol builder's address.
    ///      Tips go directly to the builder without MEV-Boost relay middlemen.
    ///      The expectedSlot parameter prevents stale execution in reorgs.
    /// @param profit Total profit from MEV execution
    /// @param tipBps Tip in basis points
    /// @param expectedSlot Expected slot number (block.number used as proxy)
    /// @return tipPaid Actual tip sent to builder coinbase
    function tipCoinbaseEPBS(uint256 profit, uint16 tipBps, uint64 expectedSlot) internal returns (uint256 tipPaid) {
        // Slot validation: prevent execution in unexpected blocks (reorg protection)
        assembly ("memory-safe") {
            if iszero(eq(number(), expectedSlot)) {
                mstore(0x00, 0x1ab7da6b) // DeadlineExpired() — reuse as slot mismatch
                revert(0x1c, 0x04)
            }
        }
        return tipCoinbase(profit, tipBps);
    }

    // ═══════════════════════════════════════════════════════════════
    //     EIP-7971/7609: PER-HOP PROFIT TRACKING
    //     TLOAD=5gas / TSTORE=12gas makes per-hop checks viable
    // ═══════════════════════════════════════════════════════════════

    /// @notice Snapshot token balance before a specific hop
    /// @dev Costs 12 gas per TSTORE at EIP-7971 pricing (vs 100 gas today)
    /// @param hopIndex The hop number (0-indexed)
    /// @param token The token to snapshot
    function snapshotHopBalance(uint8 hopIndex, address token) internal {
        uint256 bal = tokenBalance(token);
        uint256 slot = HOP_BALANCE_BASE + hopIndex;
        assembly ("memory-safe") {
            tstore(slot, bal)
        }
    }

    /// @notice Check that a hop produced positive delta
    /// @dev Costs 5 gas per TLOAD at EIP-7971 pricing (vs 100 gas today)
    /// @param hopIndex The hop number to verify
    /// @param token The token to check balance of
    /// @return delta The balance change (positive = profit)
    function checkHopProfit(uint8 hopIndex, address token) internal view returns (uint256 delta) {
        uint256 slot = HOP_BALANCE_BASE + hopIndex;
        uint256 before;
        assembly ("memory-safe") {
            before := tload(slot)
        }
        uint256 current = tokenBalance(token);
        delta = current > before ? current - before : 0;
    }

    /// @notice Snapshot a specific token's balance using token-keyed transient slot
    /// @dev Enables parallel tracking of multiple tokens across hops
    /// @param token The ERC-20 token address
    function snapshotTokenBalance(address token) internal {
        uint256 bal = tokenBalance(token);
        uint256 slot = TOKEN_SNAPSHOT_BASE + uint160(token);
        assembly ("memory-safe") {
            tstore(slot, bal)
        }
    }

    /// @notice Enforce that a specific token's balance has increased since snapshot
    /// @param token The ERC-20 token address
    /// @return profit The positive delta
    function enforceTokenProfitInvariant(address token) internal view returns (uint256 profit) {
        uint256 slot = TOKEN_SNAPSHOT_BASE + uint160(token);
        uint256 before;
        assembly ("memory-safe") {
            before := tload(slot)
        }
        uint256 current = tokenBalance(token);
        if (current <= before) revert NoProfitGenerated();
        profit = current - before;
    }

    /// @notice Assert intermediate balance >= threshold (sanity check between hops)
    /// @dev Ultra-cheap at EIP-7971 pricing: 5 gas TLOAD + comparison
    /// @param token The token to check
    /// @param minBalance Minimum expected balance
    function assertMinBalance(address token, uint256 minBalance) internal view {
        uint256 bal = tokenBalance(token);
        if (bal < minBalance) revert NoProfitGenerated();
    }

    // ═══════════════════════════════════════════════════════════════
    //                  CLZ BITMAP ROUTING (ex-CLZRouterLib)
    // ═══════════════════════════════════════════════════════════════

    /// @dev Bitmap layout (256 bits):
    ///   Bits 0-7:   DEX selector (16 DEXes: UniV2/V3/V4, Sushi, Curve, Balancer,
    ///               Pancake, Camelot, Aero, Velo, DODO, Maverick, WOOFi, TraderJoe, iZiSwap, SyncSwap)
    ///   Bits 10-17: Fee tier (for Uni V3/V4)
    ///   Bits 18-25: Bridge selector (8 bridges: Across, Stargate, LayerZero,
    ///               deBridge, Celer, CCIP, Wormhole, Hop)
    ///   Bits 26-33: Flash loan provider (8 providers: Aave, Balancer, UniV2/V3,
    ///               Morpho Blue, ERC-3156, PancakeV3, PancakeV2)
    ///   Bits 34-63: Reserved
    ///   Bits 64-255: Route-specific data (hop count, amounts, etc.)

    error InvalidDexId(uint8 dexId);
    error InvalidBridgeId(uint8 bridgeId);
    error InvalidFlashProvider(uint8 providerId);
    error EmptyBitmap();

    function extractDexId(uint256 bitmap) internal pure returns (uint8 dexId) {
        assembly ("memory-safe") {
            dexId := and(bitmap, 0xFF)
        }
    }

    function extractFeeTier(uint256 bitmap) internal pure returns (uint24 fee) {
        assembly ("memory-safe") {
            fee := and(shr(10, bitmap), 0xFF)
        }
        if (fee == 1) return 100;
        if (fee == 2) return 500;
        if (fee == 3) return 3000;
        if (fee == 4) return 10_000;
        return fee * 100;
    }

    function extractBridgeId(uint256 bitmap) internal pure returns (uint8 bridgeId) {
        assembly ("memory-safe") {
            bridgeId := and(shr(18, bitmap), 0xFF)
        }
    }

    function extractFlashProvider(uint256 bitmap) internal pure returns (uint8 providerId) {
        assembly ("memory-safe") {
            providerId := and(shr(26, bitmap), 0xFF)
        }
    }

    function extractHopCount(uint256 bitmap) internal pure returns (uint8 hops) {
        assembly ("memory-safe") {
            hops := and(shr(64, bitmap), 0xFF)
        }
    }

    function findBestDex(uint256 dexBitmap) internal pure returns (uint8 bestDexId) {
        if (dexBitmap == 0) revert EmptyBitmap();
        uint256 highBit = LibBit.fls(dexBitmap);
        // `LibBit.fls(uint256)` is always in [0, 255]. Use assembly to avoid
        // truncating casts flagged by `forge lint`.
        assembly ("memory-safe") {
            bestDexId := highBit
        }
    }

    function iterateDexes(uint256 dexBitmap) internal pure returns (uint8[16] memory dexIds, uint8 count) {
        uint256 remaining = dexBitmap;
        while (remaining != 0 && count < 16) {
            uint256 highBit = LibBit.fls(remaining);
            uint8 dexId;
            // `highBit` is in [0, 255]. Use assembly to avoid truncating casts flagged by `forge lint`.
            assembly ("memory-safe") {
                dexId := highBit
            }
            dexIds[count] = dexId;
            remaining &= ~(uint256(1) << highBit);
            unchecked {
                ++count;
            }
        }
    }

    function countRoutes(uint256 bitmap) internal pure returns (uint256) {
        return LibBit.popCount(bitmap);
    }

    function validateRoute(uint256 bitmap) internal pure returns (bool valid) {
        uint8 dexId = extractDexId(bitmap);
        uint8 bridgeId = extractBridgeId(bitmap);
        uint8 flashId = extractFlashProvider(bitmap);
        return dexId <= 15 && bridgeId <= 7 && flashId <= 7;
    }
}
