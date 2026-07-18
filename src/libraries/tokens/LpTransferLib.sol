// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

/// @dev Minimal ERC-721 surface for LP-NFT moves. Hoisted to file scope
///      because Solidity does not allow nested interfaces inside a library.
interface IERC721Lp {
    /// @notice Move tokenId `tokenId` from `from` to `to` and invoke the
    ///         receiver's `onERC721Received` callback if `to` is a contract.
    /// @dev    Project consumers (`MevSafe.moveLpV3Nft`,
    ///         `LpTransferLib.moveV3`) always call with `from == address(this)`.
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
}

/// @dev Minimal ERC-6909 surface for V4 LP claims.
interface IERC6909Lp {
    /// @notice Move `amount` of token `id` from `msg.sender` to `to`.
    /// @return ok  True iff the transfer succeeded; the project requires
    ///             this to be `true` (we revert on `false`).
    function transfer(
        address to,
        uint256 id,
        uint256 amount
    ) external returns (bool ok);

    /// @notice Authorize `operator` to move ALL of `msg.sender`'s ERC-6909
    ///         token IDs.
    /// @dev    BACKDOOR closure: project policy disallows this on the auth
    ///         contracts via the per-target structured `executeErc6909Batch`
    ///         flow. Callers that smuggle this selector through generic
    ///         `execute` are blocked at the entry point.
    /// @return ok  True iff the operator change succeeded.
    function setOperator(
        address operator,
        bool approved
    ) external returns (bool ok);
}

/// @title  LpTransferLib
/// @author mev-arbitrum
/// @notice Typed helpers for moving liquidity-provider positions held by
///         the Safe / Executor. Three LP families on Arbitrum:
///           V2_ERC20    — Camelot V2, Sushi, Curve V1, etc.
///           V3_NFT      — Uniswap V3 PositionManager (and V3-clones)
///           V4_ERC6909  — Uniswap V4 PoolManager claims
///
///         All call sites should normalise through this library so the
///         AtomicCollateral / LpMoved events have a uniform shape and
///         the executor's nonReentrant scope covers the transfer.
///
///         Source: F-13 + F-17 + F-23/F-24 of the Safe + 4337 factor sheet.
library LpTransferLib {
    using SafeTransferLib for address;

    /// @dev Discriminated tag for `MevSafe.LpMoved` event consumers. Each
    ///      enum value maps to one of the three LP families above; the
    ///      mover function name encodes the same information at call sites.
    enum LpKind {
        V2_ERC20,
        V3_NFT,
        V4_ERC6909
    }

    /// @dev Raised on zero-address inputs to any mover. Every mover does an
    ///      explicit `pool/positionManager/poolManager == address(0) ||
    ///      to == address(0)` check up front so a misconfigured caller can't
    ///      burn an LP position to the zero address.
    /// @dev Aderyn L-12 (audit 2026-05-08): `UnknownKind` originated when
    ///      the library shape was a single dispatcher over `LpKind`; it
    ///      was replaced by discrete `moveV2` / `moveV3` / `moveV4`
    ///      helpers and has no callers since. Deleted in this pass.
    error InvalidParams();

    /// @dev Raised by `moveV4` when the ERC-6909 `transfer` returns `false`.
    error LpTransferLib__V4TransferFailed();

    /// @dev Raised by `setV4Operator` when ERC-6909 `setOperator` returns `false`.
    error LpTransferLib__V4SetOperatorFailed();

    // -- Movers -------------------------------------------------------------

    /// @notice Move an ERC-20 LP token (V2-style) from this contract to `to`.
    /// @dev    Solady `safeTransfer` reverts on failure (revert-with-bytes
    ///         normalisation). The library is `internal`-only so this lives
    ///         inline at the call site.
    /// @param  pool     V2-style ERC-20 pair token contract.
    /// @param  amount   Quantity of pool tokens to move.
    /// @param  to       Recipient.
    function moveV2(
        address pool,
        uint256 amount,
        address to
    ) internal {
        if (pool == address(0) || to == address(0)) revert InvalidParams();
        pool.safeTransfer(to, amount);
    }

    /// @notice Move a V3 LP NFT (ERC-721) by tokenId from this contract to `to`.
    /// @dev    Uses `safeTransferFrom` so receiver-side `onERC721Received`
    ///         is enforced. Receiver MUST be an EOA or implement the
    ///         ERC-721 receiver interface.
    /// @param  positionManager  Uniswap V3 PositionManager (or clone).
    /// @param  tokenId          Position NFT tokenId.
    /// @param  to               Recipient.
    function moveV3(
        address positionManager,
        uint256 tokenId,
        address to
    ) internal {
        if (positionManager == address(0) || to == address(0)) revert InvalidParams();
        IERC721Lp(positionManager).safeTransferFrom(address(this), to, tokenId);
    }

    /// @notice Move a V4 LP claim (ERC-6909) by (id, amount).
    /// @dev    Aderyn L-11 (audit 2026-05-08): the IERC6909 `transfer` here is
    ///         ERC-6909, not ERC-20 — the detector is mis-applied. The `bool`
    ///         return IS checked via `require(ok, ...)` immediately below.
    /// @param  poolManager  V4 PoolManager (ERC-6909 claim ledger).
    /// @param  id           Pool claim ID (V4 currency claim).
    /// @param  amount       Quantity of claim units to move.
    /// @param  to           Recipient.
    function moveV4(
        address poolManager,
        uint256 id,
        uint256 amount,
        address to
    ) internal {
        if (poolManager == address(0) || to == address(0)) revert InvalidParams();
        bool ok = IERC6909Lp(poolManager).transfer(to, id, amount);
        if (!ok) revert LpTransferLib__V4TransferFailed();
    }

    /// @notice Authorize an operator to manage V4 positions on the holder's
    ///         behalf (F-13). Critical event — broadcast via caller.
    /// @dev    Reachable only through structured per-target paths
    ///         (`MevSafe.setV4Operator`, `MevSafe.executeErc6909Batch`,
    ///         `MevBotDelegate.executeErc6909Batch`). Generic execute paths
    ///         block this selector via the L-1 hardening gates.
    /// @param  poolManager  V4 PoolManager contract.
    /// @param  operator     Address being granted/revoked.
    /// @param  approved     True to authorize, false to revoke.
    function setV4Operator(
        address poolManager,
        address operator,
        bool approved
    ) internal {
        if (poolManager == address(0) || operator == address(0)) revert InvalidParams();
        bool ok = IERC6909Lp(poolManager).setOperator(operator, approved);
        if (!ok) revert LpTransferLib__V4SetOperatorFailed();
    }

    // @dev no EIP-7939 CLZ opportunities — only constant-time interface
    //      forwarding (no bit-counting or fixed-point math).
}
