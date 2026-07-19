# superLIB libraries

A complementary Solidity library collection (Solady-style): gas-optimized
helpers for primitives that OpenZeppelin and Solady don't cover — recent EIPs
(beacon roots, blob gas, RIP-7212 P256, BLS12-381), MEV-specific utilities,
and osaka-target bit/math helpers — gathered from the mev-arbitrum and
MEV-PARADISE workspaces. All libraries are `SPDX MIT`,
`pragma solidity ^0.8.35`, and compile against `evm_version = "osaka"` (some
use the `clz` opcode and transient storage).

Layout: one folder per category, sorted alphabetically within.

## math
| Library | Purpose |
|---|---|
| `BitMath` | Bit-manipulation helpers (most/least-significant bit, masks, next-power-of-2, top-N bits). |

## crypto
| Library | Purpose |
|---|---|
| `BLSLib` | BLS12-381 calldata-native pairing verification ("dumb contract, smart Rust"). |
| `P256Precompile` | secp256r1 (EIP-7951 P256VERIFY) utilities: cached availability, curve/range checks, raw verify. |

## evm
| Library | Purpose |
|---|---|
| `BeaconRootLib` | Beacon block-root reads (EIP-4788). |
| `BlobGasLib` | Blob base-fee / blob-gas helpers (EIP-4844). |

## transient
| Library | Purpose |
|---|---|
| `TransientReentrancy` | Reentrancy guard using transient storage (`TSTORE`/`TLOAD`). |
| `TransientStorage` | Typed transient-storage slot helpers. |

## deploy
| Library | Purpose |
|---|---|
| `HookCreate2` | `CREATE2` deploy for mined Uniswap v4 hook addresses (bubbles up constructor revert data). |
| `UniversalDeployment` | Deterministic universal deployment helper. |

## tokens
| Library | Purpose |
|---|---|
| `LpTransferLib` | LP-token transfer helpers (Solady `SafeTransferLib`). |
| `TokenStandardIds` | Token-standard (ERC-20/721/1155/…) detection. |

## dex
| Library | Purpose |
|---|---|
| `LibSlippage` | Slippage math (Solady `FixedPointMathLib`). |
| `LibUniswap` | Uniswap pair/quote helpers. |
| `RouterRegistry` | DEX router registry / dispatch table. |

## mev
| Library | Purpose |
|---|---|
| `FrontrunCalldata` | Frontrun calldata construction/analysis (generic math via Solady `FixedPointMathLib`). |
| `MEVReserveMath` | Reserve-shape heuristics (magnitude bucket, imbalance score, admission gate) — used by `ReserveShapeAdmission`. Built on Solady `FixedPointMathLib` + `BitMath` directly. |
| `ReserveShapeAdmission` | Reserve-shape admission checks (built on `MEVReserveMath`). |
| `StepMerging` | Swap-step merging/optimization (generic math via Solady `FixedPointMathLib`). |
| `TrustedFillerPolicy` | Trusted-filler policy checks. |

## utils
| Library | Purpose |
|---|---|
| `AccessListHelper` | EIP-2930 access-list construction. |
| `ASN1SMTCodec` | ASN.1/DER wire-format mapping + SMT-LIB2 constraint strings (off-chain interop). |
| `BytecodeAnalyzer` | On-chain bytecode/opcode introspection + ABI selector codec. |
| `SafetyLib` | Safety/guard helpers (transient, `LibBit`). |
| `SingletonArrays` | Single-element array constructors. |

---

### Deferred (not yet imported)
- `LiquidityAmounts` — needs `@uniswap/v4-core`.
- Executor-coupled set (`LibExecutorCore`, `LibExecutorAuth`, `LibExecutorPause`, `LibLiquidation`) — need mev-arbitrum's `interfaces/` + `executors/diamond/LibExecutorStorage`.

### Removed as duplicates of vendored dependencies
Per the "does OZ or Solady already do this?" bar: use the dependency directly instead.
- `CREATE3` — use `solady/utils/CREATE3.sol` (this was a verbatim copy).
- `BlockHashLib` — use `@openzeppelin/contracts/utils/Blockhash.sol` (identical EIP-2935 logic).
- `MulDivAssembly` — use `solady/utils/FixedPointMathLib.sol`'s `fullMulDiv` (the library's EIP-5000 opcode path was never wired up; it always ran the Solady-equivalent fallback).
- `CLZAdapter` — folded its two novel functions (`nextPowerOf2`, `findTopNBits`) into `BitMath`; the rest duplicated both `BitMath` (in-repo) and Solady `LibBit` (external) with no unique value.

### Trimmed (kept the value-add, dropped the duplicate part)
- `P256Precompile` — removed `verifySignature`/`verifyNative` (re-implemented Solady `P256.verifySignature`'s own precompile-then-fallback path); kept the cached-availability/curve/range utilities Solady doesn't expose. For automatic verify-with-fallback, call Solady's `P256.verifySignature` directly.
- `BLSLib` — removed `g1Add`/`g2Add` (duplicated Solady `BLS.add`, zero callers); kept the calldata-native pairing verification, which Solady's struct-based API doesn't provide.
- `HookCreate2` — removed `predict()` (verbatim duplicate of OZ's `Create2.computeAddress`); kept `deploy()`, whose revert-data bubbling is the real value-add over OZ's `Create2.deploy`.
- `MegaMEVOptimizationLib` — deleted. Of ~60 functions only 8 had any caller anywhere in the repo: 4 generic-math (`min`, `max`, `mulDiv`, `sqrt` — all Solady `FixedPointMathLib` duplicates) and 4 genuinely MEV-specific (`magnitudeBucket`, `reserveImbalanceBucket`, `rejectByReserveShape`, `liquidityClass`). Repointed `FrontrunCalldata`/`StepMerging` to call Solady's `FixedPointMathLib` directly, and extracted the 4 MEV-specific functions into `mev/MEVReserveMath.sol` (built on Solady `FixedPointMathLib` + `BitMath`), consumed by `ReserveShapeAdmission`.

### Relocated (structural, not a duplication issue)
- `TokenRiskFilter` moved to `src/TokenRiskFilter.sol` — it's a stateful `contract` (has a constructor), not a `library`, so it belongs alongside the other deployable engine contracts in `src/`, not in this tree.

Licensed under [MIT](../../LICENSE).
