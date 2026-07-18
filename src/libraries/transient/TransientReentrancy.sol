// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title  TransientReentrancy
/// @notice Per-flow reentrancy locks via EIP-1153 transient storage. Each flow
///         (flash, settlement, unlock, composition) has a distinct lock slot
///         so the locks can be active concurrently without deadlock — enabling
///         a flash callback that calls a router which internally enters our V4
///         unlock, or a composition outer flow that nests both flash and
///         settlement steps.
///
/// @dev    Distinct from `TransientStorage.sol` (flow IDENTITY tracking) and
///         distinct from Solady's `LibTransient.REENTRANCY_GUARD_SLOT` (single-slot at
///         `0x8000000000ab143c06`). Existing project contracts continue to use
///         Solady's mixin; this library is available for future contracts that
///         need per-flow concurrency (e.g. a future UniversalRouter).
///
///         Slots are derived from `keccak256("mev-arbitrum.TransientReentrancy.v1.<name>")`
///         to avoid collisions with `TransientStorage.sol`'s `keccak256(label) - 1`
///         slot space and Solady's compact 9-byte slot.
///
///         Locks auto-clear at end-of-tx by EIP-1153 semantics; explicit
///         `release(...)` calls in code are defense-in-depth and required for
///         correctness within a single tx that re-enters the same flow.
library TransientReentrancy {
    // -- Types -------------------------------------------------------------

    /// @notice Flow kinds. Stable ordinals — do NOT reorder.
    /// @dev    `Flash`       — flash-loan callbacks (Aave/Morpho/ERC3156/UniV3 flash)
    ///         `Settlement`  — CoW + UniswapX settlement / matchInternal flow
    ///         `Unlock`      — V4 PoolManager unlock callback / Balancer V3 unlock
    ///         `Composition` — composeFourLeg outer flow
    enum FlowKind {
        Flash,
        Settlement,
        Unlock,
        Composition
    }

    // -- Slot constants (compile-time evaluated) ---------------------------

    /// @dev `keccak256("mev-arbitrum.TransientReentrancy.v1.flash")`.
    bytes32 internal constant FLASH_LOCK_SLOT = 0x1e6068abbbc7a8f7ee8f49cce9513c4af2cc1cddc14d07d8eccff99141d70809;

    /// @dev `keccak256("mev-arbitrum.TransientReentrancy.v1.settlement")`.
    bytes32 internal constant SETTLEMENT_LOCK_SLOT = 0x159e5db5d023ee5760a54e08ca647f0b7d6104a8c891585e457a36ff8a740649;

    /// @dev `keccak256("mev-arbitrum.TransientReentrancy.v1.unlock")`.
    bytes32 internal constant UNLOCK_LOCK_SLOT = 0x270cc28c719f49fd6282b2c69d1aa671917f22131ce40f8852c4f0c2fed0ab9e;

    /// @dev `keccak256("mev-arbitrum.TransientReentrancy.v1.composition")`.
    bytes32 internal constant COMPOSITION_LOCK_SLOT =
        0x818b2f34be7762388fffface5f38634363263a1f53180401095869b2a02a8329;

    // -- Errors ------------------------------------------------------------

    /// @notice Reentry attempted while a lock of the same flow type is held.
    /// @param  flowKind The numeric `FlowKind` ordinal that is already locked.
    error Reentrancy(uint8 flowKind);

    // -- Public API --------------------------------------------------------

    /// @notice Acquire the lock for the given flow. Reverts if already held.
    /// @dev    Caller is responsible for a paired `release(kind)` to allow
    ///         the same flow to re-enter within the same tx after the inner
    ///         work completes. Auto-clears at end-of-tx per EIP-1153.
    function acquire(
        FlowKind kind
    ) internal {
        bytes32 slot = _slot(kind);
        bool held;
        assembly ("memory-safe") {
            held := tload(slot)
        }
        if (held) revert Reentrancy(uint8(kind));
        assembly ("memory-safe") {
            tstore(slot, 1)
        }
    }

    /// @notice Release the lock for the given flow.
    /// @dev    Idempotent — safe to call from a finally-style cleanup path.
    function release(
        FlowKind kind
    ) internal {
        bytes32 slot = _slot(kind);
        assembly ("memory-safe") {
            tstore(slot, 0)
        }
    }

    /// @notice Read the lock state without modifying.
    function isHeld(
        FlowKind kind
    ) internal view returns (bool held) {
        bytes32 slot = _slot(kind);
        assembly ("memory-safe") {
            held := tload(slot)
        }
    }

    // -- Internal ----------------------------------------------------------

    /// @dev Maps `FlowKind` to its compile-time slot. The Solidity ABI's enum
    ///      bounds check guarantees `kind ∈ [0..3]`, so the final return acts
    ///      as the `Composition` branch — no unreachable revert is needed.
    function _slot(
        FlowKind kind
    ) private pure returns (bytes32) {
        if (kind == FlowKind.Flash) return FLASH_LOCK_SLOT;
        if (kind == FlowKind.Settlement) return SETTLEMENT_LOCK_SLOT;
        if (kind == FlowKind.Unlock) return UNLOCK_LOCK_SLOT;
        return COMPOSITION_LOCK_SLOT; // FlowKind.Composition (enum bounds guarantee).
    }
}
