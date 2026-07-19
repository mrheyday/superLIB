// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";
import { ReserveShapeAdmission } from "./ReserveShapeAdmission.sol";

/// @title  FrontrunCalldata — encoders + decoders for the frontrun decoder targets
/// @author mev-arbitrum
/// @notice Pure library for building and inspecting the calldata of the 5
///         canonical frontrun decoder targets (Uniswap V2, Uniswap V3
///         single/multi, Universal Router, Aave V3 liquidationCall).
///         Used by the S-5 oracle-update sandwich + future generalized
///         frontrun strategies.
///
///         Selector citations (verified with `cast sig` on 2026-05-11):
///           - V2 `swapExactTokensForTokens(uint256,uint256,address[],address,uint256)`
///             → 0x38ed1739 — Uniswap V2 Router02. Canonical source:
///             [UniswapV2Router02.sol](https://github.com/Uniswap/v2-periphery/blob/master/contracts/UniswapV2Router02.sol).
///           - V3 `exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))`
///             → 0x414bf389 — Uniswap V3 SwapRouter (periphery V1, deadline-bearing).
///             SwapRouter02's 7-tuple variant `0x04e45aaf` (no deadline) is decoded
///             on a best-effort basis.
///           - V3 `exactInput((bytes,address,uint256,uint256,uint256))`
///             → 0xc04b8d59 — SwapRouter periphery V1. SwapRouter02's 4-tuple
///             variant `0xb858183f` is decoded on a best-effort basis.
///           - Universal Router `execute(bytes,bytes[],uint256)`
///             → 0x3593564c (deadline-bearing).
///             `execute(bytes,bytes[])` → 0x24856bc3 (no deadline) — also decoded.
///           - Aave V3 `liquidationCall(address,address,address,uint256,bool)`
///             → 0x00a718a9 — Aave V3 Pool.
///           - ERC-20 `transfer(address,uint256)` → 0xa9059cbb — decoded only,
///             not encoded (per spec: rarely a useful frontrun target).
///
/// @dev    Phase F1 of the frontrun epic (2026-05-11). See
///         `.claude/skills/jaredbot-mev-frontrun/SKILL.md` for the playbook
///         this library mechanizes and `docs/architecture/03-LOCKED-STRATEGIES.md`
///         §S-5 (oracle-update sandwich) for the first production caller.
///
///         CONSTRAINTS:
///           - PURE library: no storage, no events, no logs. All errors are
///             prefixed `FrontrunCalldata__` per project convention.
///           - Calldata-direct reads via `bytes calldata` where decoding;
///             avoid memory copies on hot-path victim inspection.
///           - Math primitives borrowed from Solady (`fullMulDiv`, `sqrt`) so
///             the optimal-amount calculation is overflow-safe across the
///             documented envelope (reserves ≤ 2^113, victim amount ≤ 2^96).
///             The 2^113 wei ceiling (~10^34) dwarfs any realistic Arbitrum
///             pool size (largest WETH pool ~10^23 wei). Above-envelope
///             callers receive a `MulDivFailed` revert from Solady's
///             `fullMulDiv` rather than a return-0 unprofitable signal —
///             the worst-case-fee (γ=9970 bps) `b1OverA1²` term saturates
///             at R0 ≈ 2^113. F-01 reconciliation (audit 2026-05-11):
///             updated from the optimistic 2^128 claim to the operational
///             2^113 bound that the regression test `test_optimalV2_
///             overflowEnvelope_largeReserves_largeVictim` exercises.
library FrontrunCalldata {
    // =========================================================================
    // Selector constants
    // =========================================================================

    /// @notice V2 `swapExactTokensForTokens(uint,uint,address[],address,uint)`
    bytes4 internal constant V2_SWAP_EXACT_TOKENS_FOR_TOKENS = 0x38ed1739;

    /// @notice V3 `exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))`
    ///         — SwapRouter periphery V1 (8-tuple, includes `deadline`).
    bytes4 internal constant V3_EXACT_INPUT_SINGLE = 0x414bf389;

    /// @notice V3 `exactInputSingle((address,address,uint24,address,uint256,uint256,uint160))`
    ///         — SwapRouter02 (7-tuple, no `deadline`). Best-effort decode.
    bytes4 internal constant V3_EXACT_INPUT_SINGLE_02 = 0x04e45aaf;

    /// @notice V3 `exactInput((bytes,address,uint256,uint256,uint256))`
    ///         — SwapRouter periphery V1 (5-tuple, includes `deadline`).
    bytes4 internal constant V3_EXACT_INPUT = 0xc04b8d59;

    /// @notice V3 `exactInput((bytes,address,uint256,uint256))`
    ///         — SwapRouter02 (4-tuple, no `deadline`). Best-effort decode.
    bytes4 internal constant V3_EXACT_INPUT_02 = 0xb858183f;

    /// @notice Universal Router `execute(bytes,bytes[],uint256)` — deadline-bearing.
    bytes4 internal constant UR_EXECUTE = 0x3593564c;

    /// @notice Universal Router `execute(bytes,bytes[])` — no-deadline variant.
    bytes4 internal constant UR_EXECUTE_NO_DEADLINE = 0x24856bc3;

    /// @notice Aave V3 `liquidationCall(address,address,address,uint256,bool)`.
    bytes4 internal constant AAVE_V3_LIQUIDATION_CALL = 0x00a718a9;

    /// @notice ERC-20 `transfer(address,uint256)` — decoded only, never encoded by this library.
    bytes4 internal constant ERC20_TRANSFER = 0xa9059cbb;

    // =========================================================================
    // Universal Router command bytes (subset we decode natively)
    // =========================================================================
    //
    // The Universal Router dispatches each entry in the `commands` bytes
    // string on its low-7-bit command code. Reference:
    // <https://github.com/Uniswap/universal-router/blob/main/contracts/libraries/Commands.sol>
    //
    // We natively decode V2_SWAP_EXACT_IN, V3_SWAP_EXACT_IN, WRAP_ETH,
    // UNWRAP_WETH, and PERMIT2_TRANSFER_FROM. Other commands (V4_SWAP,
    // PAY_PORTION, SWEEP, NFT mints, EXECUTE_SUB_PLAN, …) are surfaced
    // as raw `bytes` slices with their command-byte tag so the off-chain
    // coordinator can post-process them. See `URCommand` enum below.

    /// @dev `command & FLAG_ALLOW_REVERT` is the FLAG_ALLOW_REVERT bit.
    ///      Strip with `command & COMMAND_TYPE_MASK` before dispatching.
    bytes1 internal constant FLAG_ALLOW_REVERT = 0x80;

    /// @dev Low 7 bits select the command type.
    bytes1 internal constant COMMAND_TYPE_MASK = 0x3f;

    bytes1 internal constant CMD_V3_SWAP_EXACT_IN = 0x00;
    bytes1 internal constant CMD_V3_SWAP_EXACT_OUT = 0x01;
    bytes1 internal constant CMD_PERMIT2_TRANSFER_FROM = 0x02;
    bytes1 internal constant CMD_V2_SWAP_EXACT_IN = 0x08;
    bytes1 internal constant CMD_V2_SWAP_EXACT_OUT = 0x09;
    bytes1 internal constant CMD_WRAP_ETH = 0x0b;
    bytes1 internal constant CMD_UNWRAP_WETH = 0x0c;
    bytes1 internal constant CMD_V4_SWAP = 0x10;
    bytes1 internal constant CMD_EXECUTE_SUB_PLAN = 0x21;

    /// @notice Tagged command kind for `decodeURExecute` output. Mirrors the
    ///         on-chain command byte but is sized to a Solidity enum so the
    ///         coordinator can match exhaustively. `UNKNOWN` is the catch-all
    ///         for any command we don't natively parse.
    enum URCommand {
        V3_SWAP_EXACT_IN,
        V3_SWAP_EXACT_OUT,
        PERMIT2_TRANSFER_FROM,
        V2_SWAP_EXACT_IN,
        V2_SWAP_EXACT_OUT,
        WRAP_ETH,
        UNWRAP_WETH,
        V4_SWAP,
        EXECUTE_SUB_PLAN,
        UNKNOWN
    }

    // =========================================================================
    // Per-target structs (decoded shape)
    // =========================================================================

    /// @notice Decoded shape of `V2_SWAP_EXACT_TOKENS_FOR_TOKENS`.
    struct V2SwapExactInParams {
        uint256 amountIn;
        uint256 amountOutMin;
        address[] path;
        address to;
        uint256 deadline;
    }

    /// @notice Decoded shape of `V3_EXACT_INPUT_SINGLE` (periphery V1, 8-tuple).
    ///         For SwapRouter02 (`V3_EXACT_INPUT_SINGLE_02`, 7-tuple)
    ///         `deadline` is set to `0` and the rest of the struct populated.
    struct V3ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline; // 0 for SwapRouter02 selector
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice SwapRouter02 V3 `exactInputSingle` shape without `deadline`.
    struct V3ExactInputSingle02Params {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Decoded shape of `V3_EXACT_INPUT` (periphery V1, 5-tuple).
    ///         For SwapRouter02 (`V3_EXACT_INPUT_02`, 4-tuple) `deadline = 0`.
    struct V3ExactInputParams {
        bytes path; // packed (token0 | uint24 fee | token1 | uint24 fee | … | tokenN)
        address recipient;
        uint256 deadline; // 0 for SwapRouter02 selector
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    /// @notice Decoded shape of Aave V3 `liquidationCall`.
    struct AaveLiquidationCallParams {
        address collateralAsset;
        address debtAsset;
        address user;
        uint256 debtToCover;
        bool receiveAToken;
    }

    /// @notice One decoded UR command — tagged for `URCommand`. For commands
    ///         we natively parse, `decoded` carries the ABI-decoded tuple
    ///         (e.g., V2SwapExactInInput packed); for `UNKNOWN` it carries
    ///         the raw input bytes verbatim. `allowRevert` mirrors the
    ///         FLAG_ALLOW_REVERT bit of the original command byte.
    struct URCommandStep {
        URCommand kind;
        bool allowRevert;
        bytes rawInput; // verbatim inputs[i] — same bytes UR would dispatch on
    }

    /// @notice Decoded V2_SWAP_EXACT_IN input. Universal Router shape:
    ///         `(address recipient, uint256 amountIn, uint256 amountOutMin,
    ///           address[] path, bool payerIsUser)`
    /// @dev    Reference: `universal-router/contracts/modules/uniswap/v2/V2SwapRouter.sol`.
    struct URV2SwapExactInInput {
        address recipient;
        uint256 amountIn;
        uint256 amountOutMin;
        address[] path;
        bool payerIsUser;
    }

    /// @notice Decoded V3_SWAP_EXACT_IN input. Universal Router shape:
    ///         `(address recipient, uint256 amountIn, uint256 amountOutMin,
    ///           bytes path, bool payerIsUser)`
    ///         where `path` is the V3 packed encoding
    ///         `tokenA | uint24 fee | tokenB | uint24 fee | … | tokenZ`.
    /// @dev    Reference: `universal-router/contracts/modules/uniswap/v3/V3SwapRouter.sol`.
    struct URV3SwapExactInInput {
        address recipient;
        uint256 amountIn;
        uint256 amountOutMin;
        bytes path;
        bool payerIsUser;
    }

    // =========================================================================
    // Errors
    // =========================================================================

    error FrontrunCalldata__CalldataTooShort();
    error FrontrunCalldata__UnknownSelector(bytes4 selector);
    error FrontrunCalldata__EmptyPath();
    error FrontrunCalldata__InvalidV3PathLength(uint256 length);
    error FrontrunCalldata__InvalidReserves();
    error FrontrunCalldata__InvalidFeeBps(uint256 feeBps);
    error FrontrunCalldata__InvalidMarginBps(uint256 marginBps);

    // =========================================================================
    // Selector helpers
    // =========================================================================

    /// @notice Read the first 4 bytes of `data` as a selector.
    /// @dev    Reverts `FrontrunCalldata__CalldataTooShort` if `data.length < 4`.
    function selectorOf(
        bytes calldata data
    ) internal pure returns (bytes4 sel) {
        if (data.length < 4) revert FrontrunCalldata__CalldataTooShort();
        assembly ("memory-safe") {
            sel := calldataload(data.offset)
        }
    }

    /// @notice True iff `data`'s selector matches one of the frontrun decoder
    ///         targets (including the SwapRouter02 + UR-no-deadline variants).
    function isFrontrunTarget(
        bytes calldata data
    ) internal pure returns (bool) {
        if (data.length < 4) return false;
        bytes4 sel = selectorOf(data);
        return sel == V2_SWAP_EXACT_TOKENS_FOR_TOKENS //
            || sel == V3_EXACT_INPUT_SINGLE //
            || sel == V3_EXACT_INPUT_SINGLE_02 //
            || sel == V3_EXACT_INPUT //
            || sel == V3_EXACT_INPUT_02 //
            || sel == UR_EXECUTE //
            || sel == UR_EXECUTE_NO_DEADLINE //
            || sel == AAVE_V3_LIQUIDATION_CALL //
            || sel == ERC20_TRANSFER;
    }

    // =========================================================================
    // V2 swapExactTokensForTokens
    // =========================================================================

    /// @notice Encode the calldata for `IUniswapV2Router02.swapExactTokensForTokens`.
    /// @param  amountIn      Tokens to sell (exact-input).
    /// @param  amountOutMin  Minimum tokens to receive (slippage floor).
    /// @param  path          Hop path — `[tokenIn, ..., tokenOut]`, length ≥ 2.
    /// @param  to            Recipient of the output tokens.
    /// @param  deadline      Unix timestamp after which the call reverts.
    /// @return The encoded calldata, including the 4-byte selector.
    function encodeV2SwapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    ) internal pure returns (bytes memory) {
        if (path.length < 2) revert FrontrunCalldata__EmptyPath();
        return abi.encodeWithSelector(V2_SWAP_EXACT_TOKENS_FOR_TOKENS, amountIn, amountOutMin, path, to, deadline);
    }

    /// @notice Decode V2 `swapExactTokensForTokens` calldata.
    /// @dev    Reverts on unexpected selector.
    function decodeV2SwapExactTokensForTokens(
        bytes calldata data
    ) internal pure returns (V2SwapExactInParams memory params) {
        bytes4 sel = selectorOf(data);
        if (sel != V2_SWAP_EXACT_TOKENS_FOR_TOKENS) revert FrontrunCalldata__UnknownSelector(sel);
        // Strip the 4-byte selector and abi.decode the rest.
        (params.amountIn, params.amountOutMin, params.path, params.to, params.deadline) =
            abi.decode(data[4:], (uint256, uint256, address[], address, uint256));
    }

    // =========================================================================
    // V3 exactInputSingle
    // =========================================================================

    /// @notice Encode `IV3SwapRouter.exactInputSingle` calldata against the
    ///         deadline-bearing periphery-V1 selector (`0x414bf389`).
    /// @dev    For the SwapRouter02 7-tuple variant (selector `0x04e45aaf`,
    ///         no deadline), use the off-chain encoder; this library defaults
    ///         to V1 per the project's spec.
    function encodeV3ExactInputSingle(
        V3ExactInputSingleParams memory params
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(V3_EXACT_INPUT_SINGLE, params);
    }

    /// @notice Decode V3 `exactInputSingle` calldata. Accepts both the
    ///         8-tuple periphery-V1 selector and the 7-tuple SwapRouter02
    ///         selector; for the 02 variant `deadline` is set to 0.
    function decodeV3ExactInputSingle(
        bytes calldata data
    ) internal pure returns (V3ExactInputSingleParams memory params) {
        bytes4 sel = selectorOf(data);
        if (sel == V3_EXACT_INPUT_SINGLE) {
            // Periphery V1 — the params tuple is encoded inline (8 head words,
            // all static), matching `abi.encodeWithSelector(sel, p.tokenIn, …, p.sqrtPriceLimitX96)`.
            return abi.decode(data[4:], (V3ExactInputSingleParams));
        } else if (sel == V3_EXACT_INPUT_SINGLE_02) {
            return _decodeV3ExactInputSingle02(data[4:]);
        } else {
            revert FrontrunCalldata__UnknownSelector(sel);
        }
    }

    /// @dev Converts the 7-field SwapRouter02 tuple into the canonical library shape.
    function _decodeV3ExactInputSingle02(
        bytes calldata body
    ) private pure returns (V3ExactInputSingleParams memory params) {
        V3ExactInputSingle02Params memory decoded = abi.decode(body, (V3ExactInputSingle02Params));
        params.tokenIn = decoded.tokenIn;
        params.tokenOut = decoded.tokenOut;
        params.fee = decoded.fee;
        params.recipient = decoded.recipient;
        params.amountIn = decoded.amountIn;
        params.amountOutMinimum = decoded.amountOutMinimum;
        params.sqrtPriceLimitX96 = decoded.sqrtPriceLimitX96;
    }

    // =========================================================================
    // V3 exactInput (multi-hop)
    // =========================================================================

    /// @notice Encode `IV3SwapRouter.exactInput` calldata against the
    ///         deadline-bearing periphery-V1 selector (`0xc04b8d59`).
    /// @dev    The canonical signature is `exactInput(ExactInputParams)`
    ///         — a single dynamic-struct argument, not a flat tuple.
    ///         Solidity ABI emits an outer 0x20 offset wrapper for the
    ///         struct head, then the struct's own inner offsets / tail.
    ///         Encoding the five fields flat (without the outer wrapper)
    ///         produces calldata Uniswap would reject. We pass the struct
    ///         as a whole to `abi.encodeWithSelector` so Solidity emits
    ///         the correct outer-struct shape.
    function encodeV3ExactInput(
        V3ExactInputParams memory params
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(V3_EXACT_INPUT, params);
    }

    /// @notice Encode the SwapRouter02 (no-deadline, 4-field struct) variant
    ///         of `exactInput`. Selector `0xb858183f`.
    /// @dev    The `V3ExactInputParams` library struct carries a `deadline`
    ///         field that the 4-field variant doesn't have; we cannot use
    ///         `abi.encodeWithSelector(V3_EXACT_INPUT_02, params)` because
    ///         that would emit 5 fields. We hand-build the calldata: outer
    ///         struct offset (0x20) || abi.encode of the 4 fields.
    function encodeV3ExactInput02(
        bytes memory path,
        address recipient,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) internal pure returns (bytes memory) {
        bytes memory inner = abi.encode(path, recipient, amountIn, amountOutMinimum);
        return abi.encodePacked(V3_EXACT_INPUT_02, uint256(0x20), inner);
    }

    /// @notice Decode V3 `exactInput` calldata. Accepts both the 5-field
    ///         periphery-V1 selector and the 4-field SwapRouter02 selector.
    /// @dev    The canonical signature wraps params in an outer dynamic
    ///         struct. After the 4-byte selector, the head starts with a
    ///         32-byte offset (0x20) pointing to the struct's body. We
    ///         slice past `selector + outer-offset` (4 + 32 = 36 bytes)
    ///         and decode the inner flat-tuple shape.
    function decodeV3ExactInput(
        bytes calldata data
    ) internal pure returns (V3ExactInputParams memory params) {
        bytes4 sel = selectorOf(data);
        if (sel == V3_EXACT_INPUT) {
            (params.path, params.recipient, params.deadline, params.amountIn, params.amountOutMinimum) =
                abi.decode(data[36:], (bytes, address, uint256, uint256, uint256));
        } else if (sel == V3_EXACT_INPUT_02) {
            (params.path, params.recipient, params.amountIn, params.amountOutMinimum) =
                abi.decode(data[36:], (bytes, address, uint256, uint256));
            params.deadline = 0;
        } else {
            revert FrontrunCalldata__UnknownSelector(sel);
        }
    }

    /// @notice Parse a V3 packed path into its `tokens[]` and `fees[]`.
    /// @dev    V3 path layout: `tokenA(20) | uint24 fee(3) | tokenB(20) |
    ///         uint24 fee(3) | … | tokenZ(20)`. For N hops there are N+1
    ///         tokens and N fees; total length is `20*(N+1) + 3*N = 23*N + 20`.
    function parseV3Path(
        bytes memory path
    ) internal pure returns (address[] memory tokens, uint24[] memory fees) {
        uint256 pathLen = path.length;
        if (pathLen < 43) revert FrontrunCalldata__InvalidV3PathLength(pathLen);
        // (pathLen - 20) must be divisible by 23.
        if ((pathLen - 20) % 23 != 0) revert FrontrunCalldata__InvalidV3PathLength(pathLen);

        uint256 hopCount = (pathLen - 20) / 23;
        tokens = new address[](hopCount + 1);
        fees = new uint24[](hopCount);

        assembly ("memory-safe") {
            // path memory layout: [length (32B)][data ...].
            let dataPtr := add(path, 0x20)

            // tokens[0] — bytes 0..20.
            mstore(add(tokens, 0x20), shr(96, mload(dataPtr)))

            // Loop hops.
            for {
                let i := 0
            } lt(i, hopCount) {
                i := add(i, 1)
            } {
                // Each hop is 23 bytes: 3 byte fee + 20 byte next token.
                // Offset of hop i's fee = 20 + 23*i.
                let hopOff := add(20, mul(i, 23))
                // Fee — top 3 bytes of the 32-byte word at offset hopOff.
                let feeWord := mload(add(dataPtr, hopOff))
                mstore(add(fees, add(0x20, mul(i, 0x20))), shr(232, feeWord))
                // Next token — 20 bytes at offset hopOff + 3.
                let tokWord := mload(add(dataPtr, add(hopOff, 3)))
                mstore(add(tokens, add(0x20, mul(add(i, 1), 0x20))), shr(96, tokWord))
            }
        }
    }

    /// @notice Pack `tokens[]` and `fees[]` into a V3 path. Inverse of
    ///         `parseV3Path`. `fees.length` must equal `tokens.length - 1`.
    /// @dev    The assembly writes 32-byte slots starting at `hopOff` and
    ///         `hopOff + 3` for each hop. On the final hop these stores
    ///         extend past the nominal path length (e.g. for `hopCount = 3`,
    ///         `path.length = 89` rounds to a 96-byte allocation but the
    ///         last token write reaches byte 100). To keep the writes
    ///         strictly inside the allocated `bytes` region — and to make
    ///         the `memory-safe` annotation correct — we over-allocate by
    ///         32 bytes, then restore the canonical length post-write.
    function encodeV3Path(
        address[] memory tokens,
        uint24[] memory fees
    ) internal pure returns (bytes memory path) {
        uint256 hopCount = fees.length;
        if (tokens.length != hopCount + 1) revert FrontrunCalldata__InvalidV3PathLength(tokens.length);
        if (hopCount == 0) revert FrontrunCalldata__EmptyPath();

        uint256 trueLen = 20 + 23 * hopCount;
        // Over-allocate by 32 bytes so the last mstore stays in-bounds.
        path = new bytes(trueLen + 32);
        assembly ("memory-safe") {
            let dataPtr := add(path, 0x20)
            // First token.
            mstore(dataPtr, shl(96, mload(add(tokens, 0x20))))
            // Each hop: fee(3) + token(20).
            for {
                let i := 0
            } lt(i, hopCount) {
                i := add(i, 1)
            } {
                let hopOff := add(20, mul(i, 23))
                // Fee at hopOff (3 high bytes of the 32-byte slot we write).
                // Use shl(232) to put the uint24 in the high 3 bytes.
                let feeVal := mload(add(fees, add(0x20, mul(i, 0x20))))
                // Write 32-byte word but only fee's high 3 bytes matter — subsequent
                // token write will overlap and overwrite the low bytes.
                mstore(add(dataPtr, hopOff), shl(232, feeVal))
                // Next token after the 3 fee bytes.
                let nextTok := mload(add(tokens, add(0x20, mul(add(i, 1), 0x20))))
                mstore(add(dataPtr, add(hopOff, 3)), shl(96, nextTok))
            }
            // Restore canonical length — abi.encode + Solidity bytes consumers
            // rely on `path.length` returning trueLen.
            mstore(path, trueLen)
        }
    }

    // =========================================================================
    // Universal Router execute
    // =========================================================================

    /// @notice Encode UR `execute(bytes commands, bytes[] inputs, uint256 deadline)`.
    /// @dev    `commands.length` must equal `inputs.length`. No further
    ///         validation — caller is responsible for command/input shape.
    function encodeURExecute(
        bytes memory commands,
        bytes[] memory inputs,
        uint256 deadline
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(UR_EXECUTE, commands, inputs, deadline);
    }

    /// @notice Decode UR `execute(...)` calldata into the per-command shape.
    /// @dev    Accepts both the deadline-bearing (`0x3593564c`) and
    ///         no-deadline (`0x24856bc3`) selectors. For the no-deadline
    ///         variant, `deadline` is set to 0.
    ///
    ///         Each entry in `steps` is tagged with its `URCommand` enum
    ///         and carries the raw `inputs[i]` bytes verbatim. The two
    ///         entry points downstream callers want are:
    ///           - `decodeURV2SwapExactIn(step.rawInput)` →
    ///             `URV2SwapExactInInput`
    ///           - `decodeURV3SwapExactIn(step.rawInput)` →
    ///             `URV3SwapExactInInput`
    function decodeURExecute(
        bytes calldata data
    ) internal pure returns (URCommandStep[] memory steps, uint256 deadline) {
        bytes4 sel = selectorOf(data);
        // Slither cannot prove the selector dispatch below assigns both locals
        // on every non-reverting path. `UR_EXECUTE` and `UR_EXECUTE_NO_DEADLINE`
        // both assign before use; all other selectors revert.
        // slither-disable-next-line uninitialized-local
        bytes memory commands;
        // slither-disable-next-line uninitialized-local
        bytes[] memory inputs;
        if (sel == UR_EXECUTE) {
            (commands, inputs, deadline) = abi.decode(data[4:], (bytes, bytes[], uint256));
        } else if (sel == UR_EXECUTE_NO_DEADLINE) {
            (commands, inputs) = abi.decode(data[4:], (bytes, bytes[]));
            deadline = 0;
        } else {
            revert FrontrunCalldata__UnknownSelector(sel);
        }

        uint256 n = commands.length;
        // If commands and inputs lengths disagree, surface as truncated steps
        // — UR itself would revert at dispatch, but we let the caller decide.
        uint256 outLen = FixedPointMathLib.min(n, inputs.length);
        steps = new URCommandStep[](outLen);
        for (uint256 i = 0; i < outLen; ++i) {
            bytes1 raw = commands[i];
            steps[i] = URCommandStep({
                kind: _classifyURCommand(raw), allowRevert: (raw & FLAG_ALLOW_REVERT) != 0, rawInput: inputs[i]
            });
        }
    }

    /// @dev Classify a UR command byte. Strips FLAG_ALLOW_REVERT before
    ///      matching against the known command codes.
    function _classifyURCommand(
        bytes1 raw
    ) private pure returns (URCommand) {
        bytes1 cmd = raw & COMMAND_TYPE_MASK;
        if (cmd == CMD_V3_SWAP_EXACT_IN) return URCommand.V3_SWAP_EXACT_IN;
        if (cmd == CMD_V3_SWAP_EXACT_OUT) return URCommand.V3_SWAP_EXACT_OUT;
        if (cmd == CMD_PERMIT2_TRANSFER_FROM) return URCommand.PERMIT2_TRANSFER_FROM;
        if (cmd == CMD_V2_SWAP_EXACT_IN) return URCommand.V2_SWAP_EXACT_IN;
        if (cmd == CMD_V2_SWAP_EXACT_OUT) return URCommand.V2_SWAP_EXACT_OUT;
        if (cmd == CMD_WRAP_ETH) return URCommand.WRAP_ETH;
        if (cmd == CMD_UNWRAP_WETH) return URCommand.UNWRAP_WETH;
        if (cmd == CMD_V4_SWAP) return URCommand.V4_SWAP;
        if (cmd == CMD_EXECUTE_SUB_PLAN) return URCommand.EXECUTE_SUB_PLAN;
        return URCommand.UNKNOWN;
    }

    /// @notice Decode a single UR V2_SWAP_EXACT_IN input bytes blob.
    ///         Shape: `(address recipient, uint256 amountIn, uint256
    ///         amountOutMin, address[] path, bool payerIsUser)`.
    function decodeURV2SwapExactIn(
        bytes memory input
    ) internal pure returns (URV2SwapExactInInput memory out) {
        (out.recipient, out.amountIn, out.amountOutMin, out.path, out.payerIsUser) =
            abi.decode(input, (address, uint256, uint256, address[], bool));
    }

    /// @notice Decode a single UR V3_SWAP_EXACT_IN input bytes blob.
    ///         Shape: `(address recipient, uint256 amountIn, uint256
    ///         amountOutMin, bytes path, bool payerIsUser)` where `path`
    ///         is the V3 packed-encoding (see `parseV3Path`).
    function decodeURV3SwapExactIn(
        bytes memory input
    ) internal pure returns (URV3SwapExactInInput memory out) {
        (out.recipient, out.amountIn, out.amountOutMin, out.path, out.payerIsUser) =
            abi.decode(input, (address, uint256, uint256, bytes, bool));
    }

    // =========================================================================
    // Aave V3 liquidationCall
    // =========================================================================

    /// @notice Encode `IPool.liquidationCall` calldata for an Aave V3
    ///         liquidation. Used to frontrun a competing liquidator.
    /// @param  collateralAsset  Asset to seize from the unhealthy user.
    /// @param  debtAsset        Debt asset to repay.
    /// @param  user             Unhealthy user being liquidated.
    /// @param  debtToCover      Amount of `debtAsset` to repay
    ///                          (capped by Aave at 50% of debt).
    /// @param  receiveAToken    `true` to receive aTokens; `false` to
    ///                          receive the underlying collateral.
    function encodeAaveV3LiquidationCall(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
            AAVE_V3_LIQUIDATION_CALL, collateralAsset, debtAsset, user, debtToCover, receiveAToken
        );
    }

    /// @notice Decode `IPool.liquidationCall` calldata — used to inspect a
    ///         victim's pending liquidation tx (who they're targeting and
    ///         for how much) so we can decide whether to frontrun.
    function decodeAaveV3LiquidationCall(
        bytes calldata data
    ) internal pure returns (AaveLiquidationCallParams memory params) {
        bytes4 sel = selectorOf(data);
        if (sel != AAVE_V3_LIQUIDATION_CALL) revert FrontrunCalldata__UnknownSelector(sel);
        (params.collateralAsset, params.debtAsset, params.user, params.debtToCover, params.receiveAToken) =
            abi.decode(data[4:], (address, address, address, uint256, bool));
    }

    // =========================================================================
    // Optimal V2 frontrun amount (sandwich-insertion class)
    // =========================================================================

    /// @notice Compute the optimal V2 frontrun amount given victim params
    ///         and current pool state.
    ///
    /// @dev    Derivation. Let `γ = (10000 − feeBps)/10000` be the
    ///         net-of-fee scalar (Uniswap V2: feeBps = 30 → γ = 0.997).
    ///         The V2 swap formula: selling `x` of tokenIn into reserves
    ///         `(R0, R1)` yields
    ///
    ///             y = γ·x·R1 / (R0 + γ·x).
    ///
    ///         After our frontrun of size `A*`:
    ///             R0' = R0 + A*        (full deposit added)
    ///             R1' = R1·R0 / (R0 + γ·A*)
    ///
    ///         The victim then swaps `Av` through `(R0', R1')`:
    ///             outV = γ·Av·R1' / (R0' + γ·Av).
    ///
    ///         Setting `outV = Mv` and substituting `R1'` gives the
    ///         fee-aware quadratic in `A*`:
    ///
    ///             γ·Mv·A*² + Mv·[R0·(γ+1) + γ²·Av]·A*
    ///                 + Mv·R0·(R0 + γ·Av) − γ·Av·R0·R1 = 0
    ///
    ///         A* is the positive root:
    ///
    ///             A* = (−B + sqrt(B² − 4·A_quad·C_quad)) / (2·A_quad)
    ///
    ///         The "spec" formula `((R0·R1)(1+s)/(Mv(1-fee)))^0.5 − R0`
    ///         is a dimensionally-incorrect simplification (it drops Av);
    ///         we instead reinterpret `marginBps` as a SAFETY MARGIN
    ///         applied to A* to avoid putting the victim exactly on the
    ///         cliff edge of their slippage tolerance (numerical rounding
    ///         in the pool's own integer math, sequencer jitter, etc.).
    ///         A* is scaled by `(10000 − marginBps)/10000` before return.
    ///
    ///         Profitability gate: returns 0 if `getAmountOut(Av, R0, R1)
    ///         ≤ Mv` — the victim's swap has no slack relative to their
    ///         minimum, so no front-leg displacement can capture any
    ///         additional output without forcing the victim to revert.
    ///
    /// @param  victimAmountIn  Victim's `amountIn` (their full swap size).
    /// @param  victimMinOut    Victim's `amountOutMin` (their slippage tolerance).
    /// @param  reserveIn       AMM reserve of tokenIn (sell side).
    /// @param  reserveOut      AMM reserve of tokenOut (buy side).
    /// @param  feeBps          AMM swap fee in basis points (Uniswap V2 = 30,
    ///                         Curve stable ≈ 4). Must be < 10000.
    /// @param  marginBps       Safety margin to back off from the cliff edge,
    ///                         in basis points (e.g., 50 = 0.5% backoff).
    ///                         Must be < 10000.
    /// @return frontrunAmount  Wei we should swap in; 0 if the sandwich
    ///                         is unprofitable or any input is degenerate.
    ///
    /// @dev    Overflow envelope. Implemented with Solady's `fullMulDiv`
    ///         for the 512-bit-intermediate products. Safe under the
    ///         documented envelope of reserves ≤ 2^128 and
    ///         victim amount ≤ 2^96:
    ///             • `R0·R1`            ≤ 2^256 (fullMulDiv intermediate)
    ///             • `γ·Av·R0·R1/Mv`    safe via fullMulDiv even with Mv = 1
    ///             • `R0·(γ+1)`         ≤ 2^128·(2·10000) ≪ 2^256
    ///             • `γ²·Av`            ≤ 10000²·2^96 ≪ 2^256
    ///             • B_quad             ≤ 2^256 (each term fits in uint256
    ///                                   under the envelope; saturating-add
    ///                                   tightens defense-in-depth)
    ///             • B_quad²            uses `fullMulDiv` for the discriminant
    ///                                   when B_quad > 2^128
    function optimalV2FrontrunAmount(
        uint256 victimAmountIn,
        uint256 victimMinOut,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 feeBps,
        uint256 marginBps
    ) internal pure returns (uint256 frontrunAmount) {
        // ── Input sanitation ───────────────────────────────────────────────
        if (feeBps > 9_999) revert FrontrunCalldata__InvalidFeeBps(feeBps);
        if (marginBps > 9_999) revert FrontrunCalldata__InvalidMarginBps(marginBps);
        if (reserveIn == 0 || reserveOut == 0) revert FrontrunCalldata__InvalidReserves();
        if (victimAmountIn == 0 || victimMinOut == 0) return 0;

        // Reserve-shape admission (shared default policy): skip dust / lopsided
        // / shallow pools before the expensive quadratic solve. Returning 0 =
        // "do not sandwich". optimalV3FrontrunAmountApprox defers here on its
        // virtual reserves, so the V3 path inherits this gate transitively.
        if (!ReserveShapeAdmission.admit(reserveIn, reserveOut)) return 0;

        // γ as a 10000-scaled basis-points scalar — call it `gBps`.
        uint256 gBps = 10_000 - feeBps;

        // ── Profitability gate ─────────────────────────────────────────────
        //
        // outV_baseline = getAmountOut(Av, R0, R1) using the pool's exact
        // integer formula:
        //     numerator   = Av · gBps · R1
        //     denominator = R0 · 10000 + Av · gBps
        //     outV        = numerator / denominator
        //
        // If outV_baseline ≤ Mv, no slack to capture — return 0.
        {
            uint256 baselineOut = FixedPointMathLib.fullMulDiv(
                victimAmountIn * gBps, reserveOut, reserveIn * 10_000 + victimAmountIn * gBps
            );
            // Note `victimAmountIn * gBps` cannot overflow under the envelope
            // (2^96 · 10^4 ≪ 2^256). `reserveIn * 10_000` similarly safe
            // (2^128 · 10^4 ≪ 2^256). The sum is < 2^144.
            if (baselineOut < victimMinOut || baselineOut == victimMinOut) return 0;
        }

        // ── Quadratic coefficients ─────────────────────────────────────────
        //
        // A_quad = γ·Mv = gBps·Mv / 10000        (keep as raw `gBps*Mv`
        //                                         since the 2·A_quad
        //                                         denominator carries
        //                                         the same /10000 factor)
        // B_quad = Mv·[R0·(γ+1) + γ²·Av]/10000
        // C_quad = Mv·R0·(R0 + γ·Av) − γ·Av·R0·R1
        //
        // To keep all coefficients ≤ uint256 we factor the /10000 out
        // and work in the 10000-scaled domain. The discriminant
        // collapses correctly because both numerator and denominator
        // of the quadratic are multiplied by the same scale.
        //
        // Concretely:
        //   numerator_A = gBps · Mv                  (≤ 10^4 · 2^128 < 2^144)
        //   numerator_B = Mv · [R0·(10000 + gBps) + gBps²·Av / 10000]
        //                                            (uses fullMulDiv as needed)
        //   numerator_C = Mv·R0·(10000·R0 + gBps·Av)/10000 − gBps·Av·R0·R1/10000
        //
        // Let's simplify by multiplying the whole quadratic by 10000² so
        // we lose denominators:
        //   A2 = gBps·Mv·10000
        //   B2 = Mv·(R0·(10000 + gBps)·10000 + gBps²·Av)
        //   C2 = Mv·R0·(R0·10000 + gBps·Av)·10000 − gBps·Av·R0·R1·10000
        //      (= 10000 · [Mv·R0·(R0·10000 + gBps·Av) − gBps·Av·R0·R1])
        //
        // Discriminant Δ = B2² − 4·A2·C2.
        //
        // Even more cleanly: factor 10000 out of A2 (A2 = A1·10000, A1 = gBps·Mv)
        // and out of C2 (C2 = 10000·C1). Then Δ = B2² − 4·A1·C1·10000² and
        // sqrt(Δ) = 10000·sqrt(B1² − 4·A1·C1) where B1 = B2/10000.
        // The factor cancels in `−B + sqrt(Δ)`.
        //
        // So we end up computing A* = (−B1 + sqrt(B1² − 4·A1·C1)) / (2·A1)
        // with:
        //   A1 = gBps·Mv
        //   B1 = Mv·(R0·(10000 + gBps) + gBps²·Av / 10000)
        //   C1 = Mv·R0·(R0·10000 + gBps·Av) − gBps·Av·R0·R1
        //      all measured in 1·1 units (i.e., wei·wei).
        //
        // The numeric overflow review: under the envelope every product
        // here either fits or is computed with fullMulDiv. See per-term
        // safety asserts inline. Reverts via FrontrunCalldata__InvalidReserves
        // if the bounds are exceeded (defense-in-depth — should never trip).

        // A1 = gBps * victimMinOut (the quadratic's leading coefficient).
        // We never use A1 directly — the algorithm divides B1, C1 through
        // A1 inline below to keep arithmetic in uint256 range.
        uint256 gBpsAv = gBps * victimAmountIn; // ≤ 10^4 · 2^96 < 2^112

        // C1 = Mv·R0·(R0·10000 + gBps·Av) − gBps·Av·R0·R1
        //
        // We compute the two halves separately and check ordering.
        // First half:   Mv·R0·(R0·10000 + gBps·Av).
        // Second half:  gBps·Av·R0·R1.
        // Profitability gate above guarantees second half > first half
        // ⇒ C1 < 0 in signed semantics. We store its absolute value as
        // `absC1` and propagate the sign.
        uint256 c1Pos;
        uint256 c1Neg;
        {
            // Inner factor of first half: (R0·10000 + gBps·Av) ≤ 2^144.
            uint256 innerFirst = reserveIn * 10_000 + gBpsAv;
            // First half = Mv · R0 · innerFirst.
            // Mv ≤ 2^128, R0 ≤ 2^128 ⇒ product ≤ 2^256. Use fullMulDiv tricks
            // by computing in two steps via fullMulDiv(Mv, R0, 1) — but that
            // can overflow uint256. Instead, use fullMulDiv with a divisor
            // and reconstruct: this is naturally what fullMulDiv lets us do.
            //
            // The safe formulation: at most one of (Mv, R0, innerFirst) can
            // exceed 2^128. R0 ≤ 2^128 by envelope. Mv ≤ 2^128 by envelope.
            // innerFirst can be up to 2^144. The product Mv·R0 ≤ 2^256 but
            // may not fit. We compute via fullMulDiv where the third operand
            // is the innerFirst; or via 512-bit decomposition.
            //
            // Simplest correct path: use Solady fullMulDiv(Mv, R0, 1) — this
            // returns floor(Mv·R0/1) and reverts if it doesn't fit in uint256.
            // Under envelope Mv·R0 ≤ 2^256 so it must fit. Then innerFirst ≤
            // 2^144 means (Mv·R0)·innerFirst ≤ 2^400, will overflow uint256.
            //
            // So we use the discriminant formulation that scales down naturally:
            // we never need C1 itself — only the discriminant B1² − 4·A1·C1,
            // and B1 is also computed in the scaled-down domain. We rescale
            // both halves of C1 against A1 in `_solveQuadratic` below.

            // Compute first-half / A1 and second-half / A1 separately,
            // each using fullMulDiv to avoid intermediate overflow.
            // Then |C1|/A1 = (second-half − first-half) / A1 with sign tracking.
            // The quadratic root formula
            //     a = (−B1 + sqrt(B1² − 4·A1·C1)) / (2·A1)
            // can be rewritten by dividing through by A1²:
            //     a = (−(B1/A1) + sqrt((B1/A1)² − 4·(C1/A1))) / 2.
            // Where (B1/A1) and (C1/A1) fit in uint256 individually because
            // A1 = gBps·Mv ≥ 1 and both halves of B1, C1 individually are
            // bounded by Mv·envelope-stuff, which divided by Mv·gBps stays
            // bounded by envelope/gBps ≤ envelope.
            //
            // c1PosOverA1 = first-half  / A1 = R0·innerFirst / gBps
            // c1NegOverA1 = second-half / A1 = Av·R0·R1 / Mv
            //
            // For c1Neg we need floor(Av·R0·R1 / Mv) with full precision.
            // The two-step `fullMulDiv(Av, R0, Mv); fullMulDiv(result, R1, 1)`
            // form silently truncates: when Av·R0 < Mv the first step floors
            // to 0 (or a tiny integer) and the result is unusable.
            //
            // Correct path: under envelope Av ≤ 2^96 and R0 ≤ 2^128 so
            // `Av·R0` fits in uint256 (≤ 2^224). Then `fullMulDiv(Av·R0, R1, Mv)`
            // computes the final result with the necessary 512-bit intermediate.
            c1Pos = FixedPointMathLib.fullMulDiv(reserveIn, innerFirst, gBps);
            c1Neg = FixedPointMathLib.fullMulDiv(victimAmountIn * reserveIn, reserveOut, victimMinOut);
            // Defense-in-depth: profitability gate above implies c1Neg > c1Pos.
            // If the gate's integer rounding admits a slim edge case where
            // c1Neg ≤ c1Pos, fall through to 0.
            if (c1Neg < c1Pos || c1Neg == c1Pos) return 0;
        }

        // B1 = Mv · (R0·(10000 + gBps) + gBps²·Av/10000).
        // We work with B1/A1 = (R0·(10000 + gBps) + gBps²·Av/10000) / gBps
        //                    = R0·(10000 + gBps)/gBps + gBps·Av/10000.
        // Each summand fits in uint256 comfortably under the envelope.
        uint256 b1OverA1;
        {
            uint256 lhs = FixedPointMathLib.fullMulDiv(reserveIn, 10_000 + gBps, gBps);
            uint256 rhs = (gBps * victimAmountIn) / 10_000;
            b1OverA1 = lhs + rhs;
        }

        // Compute discriminant: D = (b1OverA1)² + 4·|C1|/A1 (since C1 negative
        // contributes +4·|C1|/A1 to B1² − 4·A1·C1 once we divide through A1²).
        // Then a = (−b1OverA1 + sqrt(D)) / 2.
        uint256 absC1OverA1 = c1Neg - c1Pos;
        uint256 disc;
        {
            // (b1OverA1)² — may overflow uint256 if b1OverA1 > 2^128. Under the
            // envelope b1OverA1 ≤ R0·(10000+gBps)/gBps + gBps·Av/10000
            //                   ≤ 2^128·(20000/1) + 10^4·2^96/10^4
            //                   ≤ 2^128·2^15 + 2^96
            //                   ≈ 2^143.
            // So (b1OverA1)² ≤ 2^286 — overflows uint256.
            // We rescale once more by dividing through by 4.
            //
            // Rewrite: a = (−B + sqrt(B² + 4·|C|)) / 2  ≡
            //          a = −B/2 + sqrt((B/2)² + |C|)
            // where B = b1OverA1, |C| = absC1OverA1.
            // (B/2)² ≤ 2^284 — still overflows. We need fullMulDiv-style
            // arithmetic for the inner square. Solady has `fullMulDiv(x, y, d)`
            // — for x² we can pass (x, x, 1) and it reverts if it doesn't
            // fit. So under the strict envelope (b1OverA1 ≤ 2^128 i.e. R0 ≤
            // 2^113), the square fits.
            //
            // For the broader envelope (R0 ≤ 2^128 with fee=30 → gBps=9970,
            // b1OverA1 up to ~2^143), the square would not fit and we'd
            // need a different approach. We solve this by SATURATING:
            // if b1OverA1 > sqrt(type(uint256).max) we revert defensively.
            //
            // This bound (b1OverA1 ≤ 2^128) corresponds to reserves ≤ 2^113
            // in the worst-case fee, which is still ~10^34 wei — comfortable
            // headroom over any realistic pool (largest WETH pool on
            // Arbitrum is ~10^23 wei). The envelope advertised in the
            // library NatSpec is therefore the operational envelope.
            //
            // Concretely, we require b1OverA1²  fits in uint256 and revert
            // otherwise.
            uint256 halfB = b1OverA1 / 2;
            // (halfB)² + |C|. If halfB > sqrt(uint256.max / 2), squaring
            // overflows. sqrt(uint256.max) ≈ 2^128. We use Solady's mulDiv
            // which reverts on overflow.
            uint256 halfBsq = FixedPointMathLib.fullMulDiv(halfB, halfB, 1);
            disc = halfBsq + absC1OverA1;
            // saturating-add: if absC1OverA1 forces overflow we degrade to 0.
            // (Solady has saturatingAdd; here we check explicitly.)
            if (disc < halfBsq) return 0;
        }

        uint256 sqrtDisc = FixedPointMathLib.sqrt(disc);
        // a = −b1OverA1/2 + sqrtDisc. Since the sandwich is profitable
        // (gate above) sqrtDisc > b1OverA1/2 strictly; assert and subtract.
        uint256 halfB1OverA1 = b1OverA1 / 2;
        if (sqrtDisc < halfB1OverA1 || sqrtDisc == halfB1OverA1) return 0;
        frontrunAmount = sqrtDisc - halfB1OverA1;

        // Apply safety margin.
        if (marginBps != 0) {
            frontrunAmount = (frontrunAmount * (10_000 - marginBps)) / 10_000;
        }
    }

    // =========================================================================
    // Simplified V3 frontrun amount (constant-liquidity-in-tick approximation)
    // =========================================================================

    /// @notice Simplified V3 frontrun amount assuming constant liquidity
    ///         in the current tick (no tick-crossing).
    ///
    /// @dev    THIS IS A V1 APPROXIMATION. Production-grade V3 frontrun
    ///         math requires walking the tick bitmap, computing crossings,
    ///         and accounting for fee accrual per-tick. That is beyond
    ///         scope for Phase F1 — the off-chain simulator (degenbot or
    ///         REVM) is the source of truth for V3 sizing in production.
    ///
    ///         Under the constant-liquidity assumption the V3 pool acts
    ///         as a virtual V2 pool with reserves
    ///             R0_virt = L / sqrt(P)
    ///             R1_virt = L · sqrt(P)
    ///         where `L = liquidity`, `P` the spot price. The frontrun
    ///         math then reuses `optimalV2FrontrunAmount` with a V3-style
    ///         fee (typically 500, 3000, or 10000 → 5, 30, or 100 bps).
    ///
    ///         CAVEATS (surface to caller — these break the model):
    ///           - Frontrun + victim that combined cross a tick boundary
    ///             produce a different output than this approximation.
    ///           - The bigger the swap relative to the in-tick liquidity,
    ///             the worse the approximation.
    ///           - For depths > 10% of in-tick liquidity, use the off-chain
    ///             simulator; this function is for coarse on-chain estimates.
    ///
    /// @param  victimAmountIn   Victim's amountIn.
    /// @param  victimMinOut     Victim's amountOutMin.
    /// @param  sqrtPriceX96     Current pool sqrtPrice * 2^96.
    /// @param  liquidity        In-tick liquidity (L from the V3 spec).
    /// @param  zeroForOne       Direction of the victim's swap.
    /// @param  feeBpsV3         V3 fee in basis points (500 = 5bps, 3000 = 30bps).
    /// @param  marginBps        Safety margin in basis points.
    /// @return frontrunAmount   In tokenIn wei. 0 if the model rejects.
    function optimalV3FrontrunAmountApprox(
        uint256 victimAmountIn,
        uint256 victimMinOut,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        bool zeroForOne,
        uint256 feeBpsV3,
        uint256 marginBps
    ) internal pure returns (uint256 frontrunAmount) {
        if (sqrtPriceX96 == 0 || liquidity == 0) return 0;

        // Translate V3 in-tick liquidity to virtual V2 reserves.
        //   R0_virt = L / sqrt(P)            (token0 reserve)
        //   R1_virt = L · sqrt(P)            (token1 reserve)
        // where sqrt(P) = sqrtPriceX96 / 2^96. We keep the X96 fixed-point.
        //
        // R0_virt (token0) = L · 2^96 / sqrtPriceX96
        // R1_virt (token1) = L · sqrtPriceX96 / 2^96
        //
        // Under envelope L ≤ 2^128, sqrtPriceX96 ≤ 2^160. Use fullMulDiv.
        uint256 r0Virt = FixedPointMathLib.fullMulDiv(uint256(liquidity), 1 << 96, uint256(sqrtPriceX96));
        uint256 r1Virt = FixedPointMathLib.fullMulDiv(uint256(liquidity), uint256(sqrtPriceX96), 1 << 96);

        // Pick (reserveIn, reserveOut) from the swap direction.
        (uint256 reserveIn, uint256 reserveOut) = zeroForOne ? (r0Virt, r1Virt) : (r1Virt, r0Virt);

        // Defer to the V2 sizing — the constant-product approximation
        // makes V3 mathematically equivalent under the assumption.
        return optimalV2FrontrunAmount(victimAmountIn, victimMinOut, reserveIn, reserveOut, feeBpsV3, marginBps);
    }

    // =========================================================================
    // V2 exact-input quote helper (informational)
    // =========================================================================

    /// @notice Exact-input quote for a V2-style constant-product swap.
    /// @dev    Pure helper mirroring `UniswapV2Library.getAmountOut`.
    ///         Useful for tests + the profitability gate inspection.
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 feeBps
    ) internal pure returns (uint256 amountOut) {
        if (amountIn == 0) return 0;
        if (reserveIn == 0 || reserveOut == 0) revert FrontrunCalldata__InvalidReserves();
        if (feeBps > 9_999) revert FrontrunCalldata__InvalidFeeBps(feeBps);
        uint256 amountInWithFee = amountIn * (10_000 - feeBps);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 10_000 + amountInWithFee;
        amountOut = numerator / denominator;
    }
}
