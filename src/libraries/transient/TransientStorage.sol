// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title  TransientStorage
/// @notice Typed wrappers around the six EIP-1153 transient slots used by Executor.sol.
/// @dev    See `docs/architecture/05-EXECUTOR-CONTRACT-SPEC.md` §1 for slot purposes.
///         All slots use the `keccak256(label) - 1` derivation (here pre-computed at
///         compile time and pasted as bytes32 literals) so storage and transient
///         spaces never collide (the `-1` follows the EIP-1967 pattern).
///         Each slot is auto-cleared at end-of-tx by EIP-1153 semantics; explicit clears
///         in code are defense-in-depth.
/// @dev    Implements EIP-1153 (Transient Storage) per spec at
///         <https://eips.ethereum.org/EIPS/eip-1153>; verified 2026-05-10.
///         Uses ONLY `tload`/`tstore` opcodes for these slots — no SLOAD/SSTORE
///         touches the transient namespace, and the regular storage layout
///         derives keys from `mapping(...) -> slot N` where N starts at 0,
///         which cannot collide with the keccak-derived slots below.
library TransientStorage {
    // -- Slot constants (compile-time evaluated) ---------------------------

    /// @dev Set in `_triggerFlashLoan`; verified in flash-loan callbacks (H1).
    ///      Constant = `keccak256("Executor.expectedLender.v1") - 1`. Pinned
    ///      as a bytes32 literal so the namespace cannot drift across builds.
    bytes32 internal constant EXPECTED_LENDER_SLOT = 0x2a51345724187232c4a2728b319ec298553f3eb52eb998941ca7a0ec47b3f640;

    /// @dev Per-tx flow identifier; correlates logs across callbacks.
    ///      Constant = `keccak256("Executor.flowId.v1") - 1`.
    bytes32 internal constant FLOW_ID_SLOT = 0xa3fe3d870bd7283af33a8ef894ee9932b4710ce472ac6e764a3f66aaeb33fcf4;

    /// @dev M1 chained hash of remaining work in CoW flash-loan-router fork.
    ///      Constant = `keccak256("Executor.cumulativeHash.v1") - 1`.
    bytes32 internal constant CUMULATIVE_HASH_SLOT = 0xa6e7f4e8d6ba213eb0af2b30ea68b8d88ba85042d5b0eda49086f4f9964944a1;

    /// @dev Reentrancy guard slot (`LibTransient.REENTRANCY_GUARD_SLOT` is separate;
    ///      this one is reserved for application-level mutual exclusion across the
    ///      flash-loan dispatch state machine).
    ///      Constant = `keccak256("Executor.executing.v1") - 1`.
    /// @dev Used by: future application-layer mutex (currently dormant).
    ///      Aderyn does not flag this; documented for completeness so a
    ///      reader does not assume a dropped slot.
    bytes32 internal constant EXECUTING_SLOT = 0xee8264938d1089b5222497e075a783e89a24fbe45931de68fb25b0c8f71a0c8f;

    /// @dev Set when invoking UniswapX reactor; verified in `reactorCallback`.
    ///      Constant = `keccak256("Executor.expectedReactor.v1") - 1`.
    bytes32 internal constant EXPECTED_REACTOR_SLOT =
        0xb8d1bfe6c5e3c6955ae7b64549c13f6ebfdf63c5756ec1676c5d22189a3db090;

    /// @dev Set when invoking a Uniswap V3 pool flash; verified in
    ///      `uniswapV3FlashCallback`.
    ///      Constant = `keccak256("Executor.expectedV3Pool.v1") - 1`.
    bytes32 internal constant EXPECTED_V3_POOL_SLOT =
        0xa297b7842bb27d1df6b58814cd9c628fad9558edf61186370124926f9ce1df5a;

    /// @dev Set only around an intentional synchronous CoW Settlement call
    ///      that may invoke `Executor.transferToSettlement`.
    ///      Constant = `keccak256("executor.transient.settlementFunding") - 1`.
    bytes32 internal constant SETTLEMENT_FUNDING_SLOT =
        0x215e574dd9d7a963dbbf9a9026d05ffb821e0a371ef04d77e1358a302ee1c16a;

    /// @dev Remaining transferrable amount in the active settlement-funding window
    ///      (audit 2026-06-09 hardening — pairs with the committed token in
    ///      `SETTLEMENT_FUNDING_SLOT`, which now holds the buyToken address, not a bool).
    ///      Constant = `keccak256("executor.transient.settlementFundingRemaining") - 1`.
    bytes32 internal constant SETTLEMENT_FUNDING_REMAINING_SLOT =
        0xf8aa5f674699d699d5318f9c6ce13386f657909a4877e1f253d72eecceda5110;

    /// @dev H-1: `keccak256(abi.encode(LIQUIDATION_CALLBACK_TAG, params))` of the active flash-funded
    ///      liquidation plan (Aave / Compound / Euler / Fringe / Dolomite). Pinned by the
    ///      `LiquidationFacet._triggerLiquidationFlash` BEFORE the flash call and re-matched at the top
    ///      of `LibLiquidation.handleLiquidation` (every protocol branch). Distinct from the Morpho
    ///      debt-free lane's facet-local `_LIQ_ACTIVE_PLAN_HASH_SLOT`: the flash-funded plan reaches
    ///      `handleLiquidation` (delegatecalled from the FlashFacet callback via `LibExecutorCore` —
    ///      a separate linked library since the FlashFacet EIP-170 split, but DELEGATECALL preserves
    ///      the diamond's transient-storage namespace) via the shared dispatcher, so the slot lives
    ///      here in the shared transient namespace and is read library-side.
    ///      Constant = `keccak256("mev.executor.liquidation.flashPlanHash.v1") - 1`.
    bytes32 internal constant LIQ_FLASH_PLAN_HASH_SLOT =
        0x064f4d525e570dcbddb0ea70aeff1306f3123c6517accb81b9f19a6b30d7e8fb;

    /// @dev H-1: `keccak256(abi.encode(SANDWICH_CALLBACK_TAG, params))` of the active flash-funded
    ///      cross-pool sandwich plan (S-4). Pinned by the trigger facet BEFORE the flash call and
    ///      re-matched at the top of `LibExecutorCore.handleSandwichCrossPool`. Distinct from the
    ///      liquidation slot above so a concurrent S-4 flow cannot false-alias a liquidation flow in
    ///      the same tx. Binds the decoded plan the shared dispatcher routes on to the plan the
    ///      delegatee authorised, so a non-canonical lender cannot substitute a forged sandwich payload.
    ///      Constant = `keccak256("mev.executor.sandwich.flashPlanHash.v1") - 1`.
    bytes32 internal constant SANDWICH_FLASH_PLAN_HASH_SLOT =
        0xf64678b43788a825d01f8b001c4e07aa9c12082c52675a998a91c10566a528b5;

    /// @dev H-1: `keccak256(abi.encode(SNIPE_CALLBACK_TAG, params))` of the active flash-funded
    ///      LAUNCH-SNIPER plan. Pinned by `LaunchSniperFacet._triggerSnipeFlash` BEFORE the flash call
    ///      and re-matched at the top of `LibExecutorCore.handleSnipe`. Distinct from the liquidation
    ///      (`LIQ_FLASH_PLAN_HASH_SLOT`) and sandwich (`SANDWICH_FLASH_PLAN_HASH_SLOT`) slots so a
    ///      concurrent snipe flow cannot false-alias another flash flow in the same tx. Binds the
    ///      decoded plan the shared dispatcher routes on to the plan the delegatee authorised, so a
    ///      non-canonical lender cannot substitute a forged snipe payload (different `target` /
    ///      `riskMaskAllowed` / swap legs ⇒ different hash ⇒ revert before any token movement).
    ///      Constant = `keccak256("mev.executor.snipe.flashPlanHash.v1") - 1` (verified distinct from
    ///      every other slot above via `cast keccak`).
    bytes32 internal constant SNIPE_FLASH_PLAN_HASH_SLOT =
        0xfa57f467b217071f1a3ed2619650fbda93c0fbc1723848bf7fd7a02e7eabeb1f;

    /// @dev H-1: `keccak256(abi.encode(JIT_CALLBACK_TAG, params))` of the active flash-funded V4 in-hook
    ///      JIT plan. Pinned by `JitFacet._triggerJitFlash` BEFORE the flash call and re-matched at the
    ///      top of `LibExecutorCore.handleJit`. Distinct from the liquidation
    ///      (`LIQ_FLASH_PLAN_HASH_SLOT`), sandwich (`SANDWICH_FLASH_PLAN_HASH_SLOT`), and snipe
    ///      (`SNIPE_FLASH_PLAN_HASH_SLOT`) slots so a concurrent JIT flow cannot false-alias another
    ///      flash flow in the same tx. Binds the decoded plan the shared dispatcher routes on to the
    ///      plan the delegatee authorised, so a non-canonical lender cannot substitute a forged JIT
    ///      payload (different pool / range / amounts ⇒ different hash ⇒ revert before any token movement
    ///      or hook arming).
    ///      Constant = `keccak256("mev.executor.jit.flashPlanHash.v1") - 1` (verified distinct from every
    ///      other slot above via `cast keccak`).
    bytes32 internal constant JIT_FLASH_PLAN_HASH_SLOT =
        0xf17e16cc639faf6088866608cc03c19194e9fb357e2d16be488c1e47f74a0634;

    // -- Expected lender (H1) ----------------------------------------------

    /// @notice Pin the active flash-loan lender into transient storage.
    /// @dev    Set immediately before invoking the lender; read on the
    ///         callback to enforce H1 (`msg.sender == expected_lender`).
    ///         Cleared at end-of-tx by EIP-1153 even if the caller forgets
    ///         the explicit clear; we still emit one for nested test runs.
    /// @param  lender  The lender contract that will call back.
    function setExpectedLender(
        address lender
    ) internal {
        assembly ("memory-safe") {
            tstore(EXPECTED_LENDER_SLOT, lender)
        }
    }

    /// @notice Read the pinned lender for H1 verification.
    /// @return lender  Address pinned in `EXPECTED_LENDER_SLOT`, or zero if
    ///                 no flow is active.
    function getExpectedLender() internal view returns (address lender) {
        assembly ("memory-safe") {
            lender := tload(EXPECTED_LENDER_SLOT)
        }
    }

    /// @notice Clear the pinned lender (defense-in-depth; EIP-1153 also
    ///         clears at end-of-tx).
    function clearExpectedLender() internal {
        assembly ("memory-safe") {
            tstore(EXPECTED_LENDER_SLOT, 0)
        }
    }

    // -- Flow ID -----------------------------------------------------------

    /// @notice Pin a flow correlation ID for the duration of an entry's body.
    /// @dev    Read by callback emitters so log streams across nested calls
    ///         can be stitched together off-chain (Loki indexer / F-23
    ///         reconciliation). Settlement funding uses the dedicated
    ///         `SETTLEMENT_FUNDING_SLOT`; flow IDs are trace-only.
    /// @param  flowId  Caller-derived event correlation identifier.
    function setFlowId(
        bytes32 flowId
    ) internal {
        assembly ("memory-safe") {
            tstore(FLOW_ID_SLOT, flowId)
        }
    }

    /// @notice Read the active flow ID, or `bytes32(0)` if none.
    /// @return flowId  Pinned flow ID; zero outside an active strategy entry.
    function getFlowId() internal view returns (bytes32 flowId) {
        assembly ("memory-safe") {
            flowId := tload(FLOW_ID_SLOT)
        }
    }

    /// @notice Clear the active flow ID (defense-in-depth; EIP-1153 also
    ///         clears at end-of-tx).
    function clearFlowId() internal {
        assembly ("memory-safe") {
            tstore(FLOW_ID_SLOT, 0)
        }
    }

    // -- Cumulative hash (M1) ---------------------------------------------

    /// @notice Pin the M1 chained hash for the CoW flash-loan-router walk.
    /// @dev    Advanced one step per `borrowerCallBack` round; final round
    ///         compares the slot value against `expectedRoot`.
    /// @param  h  Hash value to pin.
    function setCumulativeHash(
        bytes32 h
    ) internal {
        assembly ("memory-safe") {
            tstore(CUMULATIVE_HASH_SLOT, h)
        }
    }

    /// @notice Read the cumulative chained hash.
    /// @return h  Current chained hash; `bytes32(0)` before round 1.
    function getCumulativeHash() internal view returns (bytes32 h) {
        assembly ("memory-safe") {
            h := tload(CUMULATIVE_HASH_SLOT)
        }
    }

    /// @notice Clear the cumulative hash (defense-in-depth).
    function clearCumulativeHash() internal {
        assembly ("memory-safe") {
            tstore(CUMULATIVE_HASH_SLOT, 0)
        }
    }

    // -- Executing flag ----------------------------------------------------

    /// @notice Set the application-level executing flag.
    /// @dev    Used by: future application-layer mutex; currently no
    ///         contract reads this slot. Reserved for the v1.1 paymaster
    ///         pool dispatch chain. Aderyn-equivalent dead-code annotation
    ///         carried on the slot constant; the helper here is documentation
    ///         parity until the consumer lands.
    /// @param  v  True to mark "executing"; false to clear.
    function setExecuting(
        bool v
    ) internal {
        assembly ("memory-safe") {
            tstore(EXECUTING_SLOT, v)
        }
    }

    /// @notice Read the application-level executing flag.
    /// @return v  True iff the slot has been set in this tx.
    function getExecuting() internal view returns (bool v) {
        assembly ("memory-safe") {
            v := tload(EXECUTING_SLOT)
        }
    }

    /// @notice Clear the executing flag (defense-in-depth).
    function clearExecuting() internal {
        assembly ("memory-safe") {
            tstore(EXECUTING_SLOT, 0)
        }
    }

    // -- Expected reactor (UniswapX) --------------------------------------

    /// @notice Pin the UniswapX reactor address that the next external call
    ///         is expected to reenter from.
    /// @dev    Read by `Executor.onlyExpectedReactor` modifier on
    ///         `reactorCallback`. Pairs with `clearExpectedReactor` even on
    ///         the failure path so a reverted UniswapX call never leaves the
    ///         slot pinned across tests (EIP-1153 also clears at tx end).
    /// @param  reactor  Reactor address to pin.
    function setExpectedReactor(
        address reactor
    ) internal {
        assembly ("memory-safe") {
            tstore(EXPECTED_REACTOR_SLOT, reactor)
        }
    }

    /// @notice Read the pinned reactor address.
    /// @return reactor  Reactor address pinned in `EXPECTED_REACTOR_SLOT`,
    ///                  or zero if no reactor flow is active.
    function getExpectedReactor() internal view returns (address reactor) {
        assembly ("memory-safe") {
            reactor := tload(EXPECTED_REACTOR_SLOT)
        }
    }

    /// @notice Clear the pinned reactor (defense-in-depth).
    function clearExpectedReactor() internal {
        assembly ("memory-safe") {
            tstore(EXPECTED_REACTOR_SLOT, 0)
        }
    }

    // -- Expected Uniswap V3 pool ----------------------------------------

    /// @notice Pin the Uniswap V3 pool expected to invoke the flash callback.
    /// @dev    This is separate from `EXPECTED_LENDER_SLOT` so V3 callbacks
    ///         can validate the reconstructed PoolKey lane without weakening
    ///         the shared lender H1 gate.
    /// @param  pool  Pool address reconstructed from factory/token0/token1/fee.
    function setExpectedV3Pool(
        address pool
    ) internal {
        assembly ("memory-safe") {
            tstore(EXPECTED_V3_POOL_SLOT, pool)
        }
    }

    /// @notice Read the pinned V3 pool for callback validation.
    /// @return pool  Address pinned in `EXPECTED_V3_POOL_SLOT`, or zero if
    ///               no V3 flash flow is active.
    function getExpectedV3Pool() internal view returns (address pool) {
        assembly ("memory-safe") {
            pool := tload(EXPECTED_V3_POOL_SLOT)
        }
    }

    /// @notice Clear the pinned V3 pool (defense-in-depth).
    function clearExpectedV3Pool() internal {
        assembly ("memory-safe") {
            tstore(EXPECTED_V3_POOL_SLOT, 0)
        }
    }

    // -- CoW settlement funding gate --------------------------------------

    /// @notice Commit the CoW settlement-funding window: the single buyToken and the
    ///         MAXIMUM amount `transferToSettlement` may forward to COW_SETTLEMENT.
    /// @dev    The Executor commits this immediately before a known CoW Settlement call
    ///         and clears it immediately after the call returns (before handling any
    ///         caught revert). A non-zero `token` marks the window active. Replaces the
    ///         former boolean gate (audit 2026-06-09 hardening): bounds the window to a
    ///         single committed (token, max) instead of an unrestricted transfer.
    /// @param  token      The committed buyToken (`address(0)` ⇒ window inactive).
    /// @param  maxAmount  Maximum cumulative amount transferrable this window.
    function setSettlementFunding(
        address token,
        uint256 maxAmount
    ) internal {
        assembly ("memory-safe") {
            tstore(SETTLEMENT_FUNDING_SLOT, token)
            tstore(SETTLEMENT_FUNDING_REMAINING_SLOT, maxAmount)
        }
    }

    /// @notice Clear the settlement-funding commitment (token + remaining).
    function clearSettlementFunding() internal {
        assembly ("memory-safe") {
            tstore(SETTLEMENT_FUNDING_SLOT, 0)
            tstore(SETTLEMENT_FUNDING_REMAINING_SLOT, 0)
        }
    }

    /// @notice The committed settlement-funding buyToken (`address(0)` ⇒ inactive).
    function settlementFundingToken() internal view returns (address token) {
        assembly ("memory-safe") {
            token := tload(SETTLEMENT_FUNDING_SLOT)
        }
    }

    /// @notice Remaining transferrable amount in the active funding window.
    function settlementFundingRemaining() internal view returns (uint256 remaining) {
        assembly ("memory-safe") {
            remaining := tload(SETTLEMENT_FUNDING_REMAINING_SLOT)
        }
    }

    /// @notice Set the remaining funding budget (used by `transferToSettlement` to
    ///         decrement after a checked transfer).
    function setSettlementFundingRemaining(
        uint256 remaining
    ) internal {
        assembly ("memory-safe") {
            tstore(SETTLEMENT_FUNDING_REMAINING_SLOT, remaining)
        }
    }

    /// @notice Whether the settlement-funding window is active (a token is committed).
    /// @return active  True iff `transferToSettlement` may fund Settlement.
    function isSettlementFundingActive() internal view returns (bool active) {
        assembly ("memory-safe") {
            active := iszero(iszero(tload(SETTLEMENT_FUNDING_SLOT)))
        }
    }

    // -- Liquidation flash plan hash (H-1) --------------------------------

    /// @notice Pin the flash-funded liquidation plan hash for the duration of the flash window.
    /// @dev    Set by `LiquidationFacet._triggerLiquidationFlash` immediately before
    ///         `LibExecutorCore.triggerFlashLoan`; re-matched at the top of `handleLiquidation`
    ///         (every protocol branch). Cleared after the flash returns (EIP-1153 also clears at tx
    ///         end). Pinning the hash binds the decoded plan the dispatcher routes on to the plan the
    ///         delegatee authorised, so a non-canonical lender cannot substitute a forged payload.
    /// @param  planHash  `keccak256(abi.encode(LIQUIDATION_CALLBACK_TAG, params))`.
    function setLiquidationPlanHash(
        bytes32 planHash
    ) internal {
        assembly ("memory-safe") {
            tstore(LIQ_FLASH_PLAN_HASH_SLOT, planHash)
        }
    }

    /// @notice Read the pinned flash-funded liquidation plan hash.
    /// @return planHash  Value pinned in `LIQ_FLASH_PLAN_HASH_SLOT`, or `bytes32(0)` if no
    ///                   flash-funded liquidation flow is active.
    function getLiquidationPlanHash() internal view returns (bytes32 planHash) {
        assembly ("memory-safe") {
            planHash := tload(LIQ_FLASH_PLAN_HASH_SLOT)
        }
    }

    /// @notice Clear the pinned liquidation plan hash (defense-in-depth; EIP-1153 also clears at
    ///         tx end).
    function clearLiquidationPlanHash() internal {
        assembly ("memory-safe") {
            tstore(LIQ_FLASH_PLAN_HASH_SLOT, 0)
        }
    }

    // -- Sandwich flash plan hash (H-1, S-4) ------------------------------

    /// @notice Pin the flash-funded cross-pool sandwich (S-4) plan hash for the flash window.
    /// @dev    Set by the trigger facet immediately before `LibExecutorCore.triggerFlashLoan`;
    ///         re-matched at the top of `handleSandwichCrossPool`. Cleared after the flash returns
    ///         (EIP-1153 also clears at tx end). Pinning the hash binds the decoded plan the dispatcher
    ///         routes on to the plan the delegatee authorised, so a non-canonical lender cannot
    ///         substitute a forged sandwich payload.
    /// @param  planHash  `keccak256(abi.encode(SANDWICH_CALLBACK_TAG, params))`.
    function setSandwichPlanHash(
        bytes32 planHash
    ) internal {
        assembly ("memory-safe") {
            tstore(SANDWICH_FLASH_PLAN_HASH_SLOT, planHash)
        }
    }

    /// @notice Read the pinned flash-funded sandwich plan hash.
    /// @return planHash  Value pinned in `SANDWICH_FLASH_PLAN_HASH_SLOT`, or `bytes32(0)` if no
    ///                   flash-funded sandwich flow is active.
    function getSandwichPlanHash() internal view returns (bytes32 planHash) {
        assembly ("memory-safe") {
            planHash := tload(SANDWICH_FLASH_PLAN_HASH_SLOT)
        }
    }

    /// @notice Clear the pinned sandwich plan hash (defense-in-depth; EIP-1153 also clears at tx end).
    function clearSandwichPlanHash() internal {
        assembly ("memory-safe") {
            tstore(SANDWICH_FLASH_PLAN_HASH_SLOT, 0)
        }
    }

    // -- Snipe flash plan hash (H-1, LAUNCH-SNIPER) -----------------------

    /// @notice Pin the flash-funded LAUNCH-SNIPER plan hash for the flash window.
    /// @dev    Set by `LaunchSniperFacet._triggerSnipeFlash` immediately before
    ///         `LibExecutorCore.triggerFlashLoan`; re-matched at the top of `handleSnipe`. Cleared
    ///         after the flash returns (EIP-1153 also clears at tx end). Pinning the hash binds the
    ///         decoded plan the dispatcher routes on to the plan the delegatee authorised, so a
    ///         non-canonical lender cannot substitute a forged snipe payload.
    /// @param  planHash  `keccak256(abi.encode(SNIPE_CALLBACK_TAG, params))`.
    function setSnipePlanHash(
        bytes32 planHash
    ) internal {
        assembly ("memory-safe") {
            tstore(SNIPE_FLASH_PLAN_HASH_SLOT, planHash)
        }
    }

    /// @notice Read the pinned flash-funded snipe plan hash.
    /// @return planHash  Value pinned in `SNIPE_FLASH_PLAN_HASH_SLOT`, or `bytes32(0)` if no
    ///                   flash-funded snipe flow is active.
    function getSnipePlanHash() internal view returns (bytes32 planHash) {
        assembly ("memory-safe") {
            planHash := tload(SNIPE_FLASH_PLAN_HASH_SLOT)
        }
    }

    /// @notice Clear the pinned snipe plan hash (defense-in-depth; EIP-1153 also clears at tx end).
    function clearSnipePlanHash() internal {
        assembly ("memory-safe") {
            tstore(SNIPE_FLASH_PLAN_HASH_SLOT, 0)
        }
    }

    // -- JIT flash plan hash (H-1, V4 in-hook JIT) ------------------------

    /// @notice Pin the flash-funded V4 in-hook JIT plan hash for the flash window.
    /// @dev    Set by `JitFacet._triggerJitFlash` immediately before `LibExecutorCore.triggerFlashLoan`;
    ///         re-matched at the top of `handleJit`. Cleared after the flash returns (EIP-1153 also
    ///         clears at tx end). Pinning the hash binds the decoded plan the dispatcher routes on to the
    ///         plan the delegatee authorised, so a non-canonical lender cannot substitute a forged JIT
    ///         payload (different pool / range / amounts ⇒ different hash ⇒ revert before any token
    ///         movement or hook arming).
    /// @param  planHash  `keccak256(abi.encode(JIT_CALLBACK_TAG, params))`.
    function setJitPlanHash(
        bytes32 planHash
    ) internal {
        assembly ("memory-safe") {
            tstore(JIT_FLASH_PLAN_HASH_SLOT, planHash)
        }
    }

    /// @notice Read the pinned flash-funded JIT plan hash.
    /// @return planHash  Value pinned in `JIT_FLASH_PLAN_HASH_SLOT`, or `bytes32(0)` if no flash-funded
    ///                   JIT flow is active.
    function getJitPlanHash() internal view returns (bytes32 planHash) {
        assembly ("memory-safe") {
            planHash := tload(JIT_FLASH_PLAN_HASH_SLOT)
        }
    }

    /// @notice Clear the pinned JIT plan hash (defense-in-depth; EIP-1153 also clears at tx end).
    function clearJitPlanHash() internal {
        assembly ("memory-safe") {
            tstore(JIT_FLASH_PLAN_HASH_SLOT, 0)
        }
    }

    // @dev no EIP-7939 CLZ opportunities — only constant-time tload/tstore.
}
