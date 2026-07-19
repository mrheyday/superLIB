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
| `BitMath` | Bit-manipulation helpers (most/least-significant bit, masks). |
| `CLZAdapter` | Count-leading-zeros over Solady `LibBit` (`clz` opcode + fallback). |
| `MulDivAssembly` | Full-precision `mulDiv` in assembly. |

## crypto
| Library | Purpose |
|---|---|
| `BLSLib` | BLS12-381 precompile helpers. |
| `P256Precompile` | secp256r1 (RIP-7212 / P256) verification via precompile, Solady `P256` fallback. |

## evm
| Library | Purpose |
|---|---|
| `BeaconRootLib` | Beacon block-root reads (EIP-4788). |
| `BlobGasLib` | Blob base-fee / blob-gas helpers (EIP-4844). |
| `BlockHashLib` | Historical block-hash access. |

## transient
| Library | Purpose |
|---|---|
| `TransientReentrancy` | Reentrancy guard using transient storage (`TSTORE`/`TLOAD`). |
| `TransientStorage` | Typed transient-storage slot helpers. |

## deploy
| Library | Purpose |
|---|---|
| `CREATE3` | Deterministic `CREATE3` deployment. |
| `HookCreate2` | `CREATE2` address derivation/mining for hooks. |
| `UniversalDeployment` | Deterministic universal deployment helper. |

## tokens
| Library | Purpose |
|---|---|
| `LpTransferLib` | LP-token transfer helpers (Solady `SafeTransferLib`). |
| `TokenRiskFilter` | Token risk / blacklist filtering. |
| `TokenStandardIds` | Token-standard (ERC-20/721/1155/…) detection. |

## dex
| Library | Purpose |
|---|---|
| `LibSlippage` | Slippage math (Solady `FixedPointMathLib`). |
| `LibUniswap` | Uniswap pair/quote helpers. |
| `RouterRegistry` | DEX router registry / dispatch table. |

## mev
Co-dependent cluster (kept together): `FrontrunCalldata`, `ReserveShapeAdmission`, and `StepMerging` build on `MegaMEVOptimizationLib`.

| Library | Purpose |
|---|---|
| `FrontrunCalldata` | Frontrun calldata construction/analysis. |
| `MegaMEVOptimizationLib` | MEV optimization primitives (shared by the cluster). |
| `ReserveShapeAdmission` | Reserve-shape admission checks. |
| `StepMerging` | Swap-step merging/optimization. |
| `TrustedFillerPolicy` | Trusted-filler policy checks. |

## utils
| Library | Purpose |
|---|---|
| `AccessListHelper` | EIP-2930 access-list construction. |
| `BytecodeAnalyzer` | On-chain bytecode analysis. |
| `SafetyLib` | Safety/guard helpers (transient, `MulDivAssembly`, `LibBit`). |
| `SingletonArrays` | Single-element array constructors. |

---

### Deferred (not yet imported)
- `LiquidityAmounts` — needs `@uniswap/v4-core`.
- Executor-coupled set (`LibExecutorCore`, `LibExecutorAuth`, `LibExecutorPause`, `LibLiquidation`) — need mev-arbitrum's `interfaces/` + `executors/diamond/LibExecutorStorage`.

Licensed under [MIT](../../LICENSE).
