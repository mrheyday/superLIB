// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import { MegaMEVOptimizationLib } from "./MegaMEVOptimizationLib.sol";

/// @title  StepMerging
/// @notice 1inch Pathfinder–style step-merging primitive in pure Solidity.
/// @dev    When multiple route candidates produce the same intermediate token
///         (e.g. two parallel paths both end at WETH before the final hop into
///         USDC), executing two separate final swaps wastes gas and splits the
///         liquidity available at that intermediate, hurting price impact.
///         This library detects shared intermediate-path signatures, sums
///         the intermediate amounts, picks the best-rate final hop, and
///         emits one consolidated final swap.
///
///         Cross-language parity with [coordinator/src/quotes/step-merging.ts].
///         Both expose the same algorithm; the only representational delta is
///         that this library uses `bytes32` token identifiers (caller hashes
///         the symbol or address) while the TS version uses opaque string
///         keys. Test fixtures are byte-identical via keccak256 of the same
///         symbol → see contracts/test/unit/StepMerging.t.sol.
///
///         Currently a v1 building block: PathFinder.sol does not yet
///         generate multi-venue route sets that need merging. When Phase F
///         lands that capability, this library is the post-processor that
///         consolidates parallel paths before final-hop emission.
library StepMerging {
    // ─── Constants (compile-time, scaled wei-style) ────────────────────────

    /// @dev 1e18 fixed-point scale (matches the TS port).
    uint256 internal constant SCALE = 1e18;

    /// @dev Trading-fee deduction in basis points (0.3% default).
    uint256 internal constant FEE_BPS = 30;

    /// @dev Price-impact growth coefficient — pure integer multiplier.
    uint256 internal constant IMPACT_EXPONENT = 3;

    /// @dev Floor on effective rate after impact + fee (10% of input value).
    uint256 internal constant MIN_EFFECTIVE_RATE_FRACTION = 10;

    /// @dev Heuristic: merged final hop costs ~62% of the best individual
    ///      final hop's gas (≈38% saving from collapsing two outer swaps
    ///      into one). Refine with empirical numbers post-launch.
    uint256 internal constant MERGED_GAS_NUMERATOR = 62;
    uint256 internal constant MERGED_GAS_DENOMINATOR = 100;

    // ─── Structs ────────────────────────────────────────────────────────────

    /// @notice One swap step: trade `amountIn` of `fromToken` for `amountOut`
    ///         of `toToken` on `dex`. All amounts are SCALE-fixed (wei-style).
    /// @dev    Field semantics:
    ///           dex            opaque dex identifier (caller chooses encoding).
    ///           fromToken      opaque token identifier (typically keccak256(symbol)).
    ///           toToken        opaque token identifier for the destination of this hop.
    ///           amountIn       SCALE-fixed input amount.
    ///           amountOut      SCALE-fixed output amount (pre-impact).
    ///           gas            heuristic gas cost for this hop (used by merge math).
    ///           poolLiquidity  SCALE-fixed depth proxy used by `simulatePriceImpactU256`.
    struct Hop {
        bytes32 dex;
        bytes32 fromToken;
        bytes32 toToken;
        uint256 amountIn;
        uint256 amountOut;
        uint256 gas;
        uint256 poolLiquidity;
    }

    /// @notice A multi-hop route. `totalOutput`/`totalGas` are precomputed
    ///         by `makeRoute` (and refreshed when a route is reconstructed
    ///         after step-merging).
    /// @dev    Field semantics:
    ///           hops         ordered hop sequence; first hop's `fromToken` is the
    ///                        path's source token, last hop's `toToken` is the destination.
    ///           totalOutput  destination-token amount (== `hops[last].amountOut`).
    ///           totalGas     sum of `hops[i].gas` over the route.
    struct Route {
        Hop[] hops;
        uint256 totalOutput;
        uint256 totalGas;
    }

    /// @notice Descriptor of one consolidated merge group, surfaced for
    ///         observability so callers can log gas savings + output
    ///         improvements.
    /// @dev    Field semantics:
    ///           signatureHash               group key (hash of intermediate-token sequence).
    ///           mergedCount                 number of input routes consolidated into one.
    ///           mergedAmountAtIntermediate  sum of pre-final-hop amounts across the group.
    ///           mergedOutput                final destination amount AFTER price-impact on
    ///                                       the consolidated input.
    ///           originalBestOutput          best individual route's `totalOutput` pre-merge
    ///                                       (for ratio comparison).
    ///           mergedGas                   gas cost of the merged route.
    ///           originalTotalGas            sum of `totalGas` over the input group.
    struct MergedGroup {
        bytes32 signatureHash;
        uint256 mergedCount;
        uint256 mergedAmountAtIntermediate;
        uint256 mergedOutput;
        uint256 originalBestOutput;
        uint256 mergedGas;
        uint256 originalTotalGas;
    }

    struct MergeBuildContext {
        Route[] routes;
        bytes32[] sigs;
        Route[] optimised;
        MergedGroup[] groups;
        bytes32 finalToken;
    }

    struct MergedRouteSummary {
        bytes32 signatureHash;
        uint256 groupSize;
        uint256 totalAtMerge;
        uint256 mergedAmountOut;
        uint256 mergedGas;
    }

    // ─── Pure helpers ──────────────────────────────────────────────────────

    /// @notice Compute the effective rate (output per unit input, scaled
    ///         by SCALE) for a swap of `amountIn` against a pool of depth
    ///         `poolLiquidity`. Pure integer arithmetic.
    ///
    /// @dev    Algebra:
    ///           ratio       = amountIn / (pool + amountIn)         // human
    ///           ratioScaled = (amountIn * SCALE) / (pool + amountIn)  // SCALE-fixed
    ///         The TS port had a stale 2x SCALE multiplier (inherited from
    ///         the upstream PoC) that flooored the result — corrected to
    ///         match this implementation. See the test that verifies a
    ///         tiny trade against deep liquidity returns ≈ SCALE - feePart.
    /// @dev    Used by: `_buildMergedRoute` and (transitively) by
    ///         `mergeStepsByIntermediate`. Aderyn flags this as "internal
    ///         function used only once" — kept as named library API so the
    ///         TS port's identical signature stays callable by tests; the
    ///         single internal caller is intentional, not dead code.
    /// @param  amountIn       Input amount (SCALE-fixed).
    /// @param  poolLiquidity  Pool depth proxy (SCALE-fixed).
    /// @return                Effective rate per unit input (SCALE-fixed),
    ///                        floored at `SCALE / MIN_EFFECTIVE_RATE_FRACTION`.
    function simulatePriceImpactU256(
        uint256 amountIn,
        uint256 poolLiquidity
    ) internal pure returns (uint256) {
        if (poolLiquidity == 0) return 0;

        uint256 denominator = poolLiquidity + amountIn;
        uint256 impactFactor = MegaMEVOptimizationLib.mulDiv(amountIn, SCALE, denominator); // [0, SCALE]

        uint256 feePart = (FEE_BPS * SCALE) / 10_000;
        uint256 impactPart = MegaMEVOptimizationLib.mulDiv(impactFactor, IMPACT_EXPONENT, 100);

        unchecked {
            uint256 effectiveRate;
            if (SCALE > feePart + impactPart) {
                effectiveRate = SCALE - feePart - impactPart;
            } else {
                effectiveRate = 0;
            }
            uint256 floorRate = SCALE / MIN_EFFECTIVE_RATE_FRACTION;
            return MegaMEVOptimizationLib.max(effectiveRate, floorRate);
        }
    }

    /// @notice Construct a Route from a list of hops; computes derived
    ///         totals. Mirrors `makeRoute` in the TS port.
    /// @dev    Used by: `_buildMergedRoute` (single internal caller). Aderyn
    ///         flags as "used only once" — intentional library API parity
    ///         with the TS port, not dead code. Off-chain tests / scripts
    ///         can construct deterministic Routes via this entry.
    /// @param  hops  Ordered hop sequence (may be empty for a degenerate route).
    /// @return r     Route with `totalOutput = hops[last].amountOut` and
    ///               `totalGas = sum(hops[i].gas)`. Empty input yields a
    ///               zero-totaled Route.
    function makeRoute(
        Hop[] memory hops
    ) internal pure returns (Route memory r) {
        r.hops = hops;
        if (hops.length == 0) return r;
        r.totalOutput = hops[hops.length - 1].amountOut;
        uint256 g = 0;
        for (uint256 i = 0; i < hops.length;) {
            g += hops[i].gas;
            unchecked {
                ++i;
            }
        }
        r.totalGas = g;
    }

    /// @notice Compute the deterministic signature of a route's
    ///         intermediate-token sequence (everything except the final
    ///         hop's `toToken`).
    /// @dev    Used as the grouping key. Equivalent to the TS port's
    ///         `route.hops.slice(0, -1).map(h => h.toToken).join('→')`
    ///         but Solidity-native via keccak256 of the packed bytes.
    ///         Used by: `mergeStepsByIntermediate` (single internal caller).
    ///         Aderyn flags as "used only once" — intentional library API
    ///         parity with the TS port; tests assert byte-equality.
    /// @param  hops  Ordered hop sequence to extract the intermediate prefix from.
    /// @return       keccak256 of the packed intermediate-token bytes, or
    ///               `bytes32(0)` for direct (1-hop) routes.
    function intermediateSignature(
        Hop[] memory hops
    ) internal pure returns (bytes32) {
        if (hops.length < 2) return bytes32(0);
        uint256 n = hops.length - 1;
        bytes32[] memory tokens = new bytes32[](n);
        for (uint256 i = 0; i < n;) {
            tokens[i] = hops[i].toToken;
            unchecked {
                ++i;
            }
        }
        return keccak256(abi.encodePacked(tokens));
    }

    // ─── Core: merge step by intermediate ──────────────────────────────────

    /// @notice Group `routes` by their intermediate-token signature and
    ///         consolidate any group with ≥ 2 routes into a single route
    ///         with one merged final hop.
    /// @param  routes      Candidate routes to consider.
    /// @param  finalToken  Destination token id; becomes `toToken` of the
    ///                     consolidated final hop.
    /// @return optimised   Route set after merging. Length ≤ routes.length.
    /// @return groups      One descriptor per consolidated group, for logs.
    function mergeStepsByIntermediate(
        Route[] memory routes,
        bytes32 finalToken
    ) internal pure returns (Route[] memory optimised, MergedGroup[] memory groups) {
        if (routes.length == 0) {
            return (new Route[](0), new MergedGroup[](0));
        }

        // First pass: classify each route's signature; compute group sizes.
        bytes32[] memory sigs = new bytes32[](routes.length);
        for (uint256 i = 0; i < routes.length;) {
            sigs[i] = routes[i].hops.length < 2 ? bytes32(0) : intermediateSignature(routes[i].hops);
            unchecked {
                ++i;
            }
        }

        // Bucket layout: parallel arrays uniqueSigs[] / counts[] /
        // representativeIdx[]. Quadratic worst case but candidate sets in
        // production are < 20 routes, so the constant beats any
        // hashing-collision contortion.
        bytes32[] memory uniqueSigs = new bytes32[](routes.length);
        uint256[] memory counts = new uint256[](routes.length);
        uint256 uniqueCount = 0;

        for (uint256 i = 0; i < routes.length;) {
            bytes32 sig = sigs[i];
            // signature = 0 → single-hop route, never merges; treat as unique.
            bool merged = false;
            if (sig != bytes32(0)) {
                for (uint256 j = 0; j < uniqueCount;) {
                    if (uniqueSigs[j] == sig) {
                        counts[j]++;
                        merged = true;
                        break;
                    }
                    unchecked {
                        ++j;
                    }
                }
            }
            if (!merged) {
                uniqueSigs[uniqueCount] = sig;
                counts[uniqueCount] = 1;
                unchecked {
                    ++uniqueCount;
                }
            }
            unchecked {
                ++i;
            }
        }

        return _buildOptimizedRoutes(routes, sigs, uniqueSigs, counts, uniqueCount, finalToken);
    }

    function _buildOptimizedRoutes(
        Route[] memory routes,
        bytes32[] memory sigs,
        bytes32[] memory uniqueSigs,
        uint256[] memory counts,
        uint256 uniqueCount,
        bytes32 finalToken
    ) private pure returns (Route[] memory optimised, MergedGroup[] memory groups) {
        // Allocate output arrays. Each unique signature contributes one
        // route to `optimised`; only signatures with count >= 2 emit a
        // MergedGroup descriptor.
        optimised = new Route[](uniqueCount);
        uint256 mergedGroupCount = 0;
        for (uint256 j = 0; j < uniqueCount;) {
            if (counts[j] > 1 && uniqueSigs[j] != bytes32(0)) {
                unchecked {
                    ++mergedGroupCount;
                }
            }
            unchecked {
                ++j;
            }
        }
        groups = new MergedGroup[](mergedGroupCount);
        MergeBuildContext memory ctx = MergeBuildContext({
            routes: routes, sigs: sigs, optimised: optimised, groups: groups, finalToken: finalToken
        });

        // Second pass: fill each output bucket. For singletons (or
        // signature == 0), copy the route as-is. For groups with count
        // ≥ 2, build the merged route.
        uint256 outIdx = 0;
        uint256 grpIdx = 0;
        for (uint256 j = 0; j < uniqueCount;) {
            bytes32 sig = uniqueSigs[j];
            if (counts[j] == 1) {
                _copySingletonRoute(ctx, sig, outIdx);
                unchecked {
                    ++outIdx;
                }
            } else {
                // sig != 0 here (we set count=1 for sig==0 routes via the
                // `merged=false` path above for any unique route). Build
                // the consolidated route.
                _storeMergedRoute(ctx, outIdx, grpIdx, sig, counts[j]);
                unchecked {
                    ++outIdx;
                    ++grpIdx;
                }
            }
            unchecked {
                ++j;
            }
        }
    }

    function _copySingletonRoute(
        MergeBuildContext memory ctx,
        bytes32 sig,
        uint256 outIdx
    ) private pure {
        for (uint256 i = 0; i < ctx.routes.length;) {
            if (ctx.sigs[i] == sig) {
                ctx.optimised[outIdx] = ctx.routes[i];
                break;
            }
            unchecked {
                ++i;
            }
        }
    }

    function _storeMergedRoute(
        MergeBuildContext memory ctx,
        uint256 outIdx,
        uint256 grpIdx,
        bytes32 sig,
        uint256 groupSize
    ) private pure {
        (Route memory mr, MergedGroup memory mg) =
            _buildMergedRoute(ctx.routes, ctx.sigs, sig, ctx.finalToken, groupSize);
        ctx.optimised[outIdx] = mr;
        ctx.groups[grpIdx] = mg;
    }

    /// @dev Internal helper — builds the consolidated route + descriptor
    ///      for one signature-group. Selects the best-rate final hop,
    ///      sums intermediate amounts, applies price-impact, and reduces
    ///      gas by the merge heuristic.
    function _buildMergedRoute(
        Route[] memory routes,
        bytes32[] memory sigs,
        bytes32 sig,
        bytes32 finalToken,
        uint256 groupSize
    ) private pure returns (Route memory mergedRoute, MergedGroup memory mg) {
        // Collect references to each route in the group. We pass groupSize
        // (already counted) so we can size the array exactly.
        Route[] memory group = new Route[](groupSize);
        uint256 fill = 0;
        for (uint256 i = 0; i < routes.length;) {
            if (sigs[i] == sig) {
                group[fill] = routes[i];
                unchecked {
                    ++fill;
                }
                if (fill == groupSize) break;
            }
            unchecked {
                ++i;
            }
        }

        // Sum amounts arriving at the merge point + find the best-rate
        // final hop in one pass.
        uint256 totalAtMerge = 0;
        Hop memory bestFinal = group[0].hops[group[0].hops.length - 1];
        uint256 bestRate = (bestFinal.amountOut * SCALE) / bestFinal.amountIn;
        for (uint256 i = 0; i < group.length;) {
            uint256 hopCount = group[i].hops.length;
            Hop memory penultimate = group[i].hops[hopCount - 2];
            Hop memory finalHop = group[i].hops[hopCount - 1];
            totalAtMerge += penultimate.amountOut;
            uint256 rate = (finalHop.amountOut * SCALE) / finalHop.amountIn;
            if (rate > bestRate) {
                bestRate = rate;
                bestFinal = finalHop;
            }
            unchecked {
                ++i;
            }
        }

        // Recompute the merged final hop with full price-impact applied
        // to the consolidated amount.
        uint256 effectiveRate = simulatePriceImpactU256(totalAtMerge, bestFinal.poolLiquidity);
        uint256 mergedAmountOut = (totalAtMerge * effectiveRate) / SCALE;
        uint256 mergedGas = (bestFinal.gas * MERGED_GAS_NUMERATOR) / MERGED_GAS_DENOMINATOR;
        MergedRouteSummary memory summary;
        summary.signatureHash = sig;
        summary.groupSize = groupSize;
        summary.totalAtMerge = totalAtMerge;
        summary.mergedAmountOut = mergedAmountOut;

        // Last intermediate token = the penultimate hop's destination of
        // any group member (all share the same signature).
        bytes32 lastIntermediate = group[0].hops[group[0].hops.length - 2].toToken;

        Hop memory mergedFinal;
        mergedFinal.dex = bestFinal.dex;
        mergedFinal.fromToken = lastIntermediate;
        mergedFinal.toToken = finalToken;
        mergedFinal.amountIn = totalAtMerge;
        mergedFinal.amountOut = mergedAmountOut;
        mergedFinal.gas = mergedGas;
        mergedFinal.poolLiquidity = bestFinal.poolLiquidity;

        // Take the FIRST group member's prefix (every member shares the
        // signature, so prefixes are equivalent up to dex/amount —
        // matches the TS port's behaviour).
        Hop[] memory baseHops = group[0].hops;
        Hop[] memory mergedHops = new Hop[](baseHops.length);
        for (uint256 i = 0; i + 1 < baseHops.length;) {
            mergedHops[i] = baseHops[i];
            unchecked {
                ++i;
            }
        }
        mergedHops[baseHops.length - 1] = mergedFinal;
        mergedRoute = makeRoute(mergedHops);
        summary.mergedGas = mergedRoute.totalGas;

        mg = _buildGroupDescriptor(group, summary);
    }

    function _buildGroupDescriptor(
        Route[] memory group,
        MergedRouteSummary memory summary
    ) private pure returns (MergedGroup memory mg) {
        uint256 originalBestOutput = 0;
        uint256 originalTotalGas = 0;
        for (uint256 i = 0; i < group.length;) {
            if (group[i].totalOutput > originalBestOutput) {
                originalBestOutput = group[i].totalOutput;
            }
            originalTotalGas += group[i].totalGas;
            unchecked {
                ++i;
            }
        }
        mg.signatureHash = summary.signatureHash;
        mg.mergedCount = summary.groupSize;
        mg.mergedAmountAtIntermediate = summary.totalAtMerge;
        mg.mergedOutput = summary.mergedAmountOut;
        mg.originalBestOutput = originalBestOutput;
        mg.mergedGas = summary.mergedGas;
        mg.originalTotalGas = originalTotalGas;
    }

    // @dev no EIP-7939 CLZ opportunities — only constant-time arithmetic
    //      (multiplication, division, subtraction). No log2 / msb /
    //      leading-zero patterns; the TS port mirrors the same shape.
}
