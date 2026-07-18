# TransientReentrancy

Per-flow EIP-1153 reentrancy locks for `mev-arbitrum/contracts`. Each flow kind owns a distinct
transient slot so locks held by different flows can co-exist without deadlock.

## Why this exists alongside Solady + TransientStorage.sol

| Library                                                      | Slot space                           | Purpose                                                                                     | Status                                                                              |
| ------------------------------------------------------------ | ------------------------------------ | ------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `solady/utils/LibTransient.sol` + `ReentrancyGuardTransient` | single slot `0x8000000000ab143c06`   | classic single-flow `nonReentrant` modifier                                                 | used by `Executor.sol`, `LiquidationExecutor.sol`, `MevSafe`, `MevPaymaster` — keep |
| `contracts/src/libraries/TransientStorage.sol`               | five `keccak256(label) - 1` slots    | flow IDENTITY (expected lender, flow id, cumulative hash, executing flag, expected reactor) | used by `Executor.sol` callback state machine — keep                                |
| `contracts/src/libraries/TransientReentrancy.sol` (this lib) | four `keccak256(...v1.<name>)` slots | per-flow LOCKS for concurrent flows                                                         | available for new contracts — Phase H landing                                       |

The motivating scenario the single-slot guard cannot handle: a flash callback (Flash lock held)
calls a swap router that internally enters our V4 `unlockCallback`. With Solady's single slot the
inner unlock would re-trigger the same guard and revert. Per-flow locks let the outer Flash and
inner Unlock co-exist. Same story for `composeFourLeg` nesting Flash + Settlement.

## Flow kinds

| Ordinal | Kind          | Typical use                                                                                                                          |
| ------- | ------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| 0       | `Flash`       | flash-loan callbacks: Aave V3 `executeOperation`, Morpho `onMorphoFlashLoan`, ERC-3156 `onFlashLoan`, UniV3 `uniswapV3FlashCallback` |
| 1       | `Settlement`  | CoW + UniswapX settlement / `matchInternal` flow                                                                                     |
| 2       | `Unlock`      | V4 PoolManager `unlockCallback`, Balancer V3 transient-unlock                                                                        |
| 3       | `Composition` | `composeFourLeg` outer flow nesting Flash + Settlement + (optional) Unlock                                                           |

Ordinals are stable — do NOT reorder. They are part of the `Reentrancy(uint8 flowKind)` error
encoding and may surface in client-side decoders.

## Slot derivation

```
FLASH_LOCK_SLOT       = keccak256("mev-arbitrum.TransientReentrancy.v1.flash")
SETTLEMENT_LOCK_SLOT  = keccak256("mev-arbitrum.TransientReentrancy.v1.settlement")
UNLOCK_LOCK_SLOT      = keccak256("mev-arbitrum.TransientReentrancy.v1.unlock")
COMPOSITION_LOCK_SLOT = keccak256("mev-arbitrum.TransientReentrancy.v1.composition")
```

The `v1.` prefix lets us add a `v2` namespace without disturbing live deployments. Slots are
evaluated at compile time. Distinctness from `TransientStorage.sol`'s `keccak256(label) - 1` slots
and Solady's `LibTransient.REENTRANCY_GUARD_SLOT` (`0x8000000000ab143c06`) is verified by the
unit-test invariant `test_slotConstants_distinctFrom*` — see
`contracts/test/unit/TransientReentrancy.t.sol`.

## EIP-1153 auto-clear semantics

Every `TSTORE` is automatically cleared at the end of the top-level transaction. Within a single tx
the lock persists across internal calls until either:

- explicit `release(kind)` — required when re-entering the same flow within the same tx after inner
  work completes;
- end-of-tx — defense-in-depth fallback so a forgotten release never corrupts a later transaction.

`release(kind)` is idempotent — safe to call from a finally-style cleanup or even when the lock is
already clear.

## When to migrate existing contracts

Not now. Phase H is library-only. The Solady mixin's single-flow guard is a correct, audited match
for `Executor.sol`, `LiquidationExecutor.sol`, `MevSafe`, and `MevPaymaster` as they exist today —
none of those entry points nests a second-flow re-entry into ours. Migration becomes interesting
only when:

1. a new contract (e.g. a future `UniversalRouter`) needs concurrent-flow nesting on the path
   described in the spec (`docs/research/UniversalRouter/UniversalRourer.md`); or
2. an existing contract grows a second entry point that would otherwise deadlock against itself
   through an external router.

Until then, `TransientReentrancy` is opt-in capability — not a replacement.

## API summary

```solidity
import {TransientReentrancy} from "../libraries/TransientReentrancy.sol";

// Acquire — reverts Reentrancy(uint8) if already held in the same tx.
TransientReentrancy.acquire(TransientReentrancy.FlowKind.Flash);

// ... inner work that may include another flow ...
TransientReentrancy.acquire(TransientReentrancy.FlowKind.Unlock); // OK — independent slot.

TransientReentrancy.release(TransientReentrancy.FlowKind.Unlock);
TransientReentrancy.release(TransientReentrancy.FlowKind.Flash);

// Inspection — read-only, no state change.
bool stillBusy = TransientReentrancy.isHeld(TransientReentrancy.FlowKind.Flash);
```
