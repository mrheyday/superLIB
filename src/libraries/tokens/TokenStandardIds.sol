// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title  TokenStandardIds
/// @author mev-arbitrum
/// @notice Canonical interface IDs (ERC-165) and ERC-6909 token-ID domain
///         prefixes used across the project's auth + executor stack.
///         Locked here to prevent collisions across F-11 / F-12 / F-14
///         (factor sheet 2026-05-07-safe-erc4337-factor-design.md).
/// @dev    EIP references active in this library:
///           - ERC-165 (Standard Interface Detection):     <https://eips.ethereum.org/EIPS/eip-165>
///           - ERC-1271 (Smart-Contract Sig Validation):   <https://eips.ethereum.org/EIPS/eip-1271>
///           - ERC-721 / ERC-1155 / ERC-3156 / ERC-4337:   per inline constants below.
///           - ERC-6909 (Minimal Multi-Token):             <https://eips.ethereum.org/EIPS/eip-6909>.
///         Verified against canonical specs 2026-05-10.
library TokenStandardIds {
    // -- ERC-165 interface IDs ---------------------------------------------

    /// @dev `bytes4(keccak256("supportsInterface(bytes4)"))` — canonical
    ///      ERC-165 interface ID per <https://eips.ethereum.org/EIPS/eip-165>.
    bytes4 internal constant IERC165_ID = 0x01ffc9a7;

    /// @dev `bytes4(keccak256("isValidSignature(bytes32,bytes)"))` — ERC-1271
    ///      magic value AND interface ID. Returned by `isValidSignature` on
    ///      successful signature verification.
    bytes4 internal constant IERC1271_ID = 0x1626ba7e;

    /// @dev `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`.
    bytes4 internal constant IERC721_RECEIVER_ID = 0x150b7a02;

    /// @dev `IERC1155Receiver.interfaceId` — covers both single + batch receivers.
    bytes4 internal constant IERC1155_RECEIVER_ID = 0x4e2312e0;

    /// @dev Return value mandated by ERC-1155 for `onERC1155Received`.
    bytes4 internal constant IERC1155_SINGLE_RECEIVED_RET = 0xf23a6e61;

    /// @dev Return value mandated by ERC-1155 for `onERC1155BatchReceived`.
    bytes4 internal constant IERC1155_BATCH_RECEIVED_RET = 0xbc197c81;

    /// @dev `bytes4(keccak256("validateUserOp((address,uint256,bytes,bytes,bytes32,uint256,bytes32,bytes,bytes),bytes32,uint256)"))`.
    ///      Same selector across ERC-4337 v0.6 / v0.7 / v0.8 dispatch APIs.
    bytes4 internal constant IACCOUNT_VALIDATE_USER_OP = 0x19822f7c;

    /// @dev `bytes4(keccak256("ERC3156FlashBorrower.onFlashLoan"))` truncated.
    ///      Used by Executor.supportsInterface to advertise generic ERC-3156 borrower.
    bytes4 internal constant IERC3156_FLASH_BORROWER_ID = 0x23e30c8b;

    // -- ERC-6909 domain prefixes (F-20) -----------------------------------
    // ID = keccak256(abi.encodePacked(<prefix>, <body>)).
    // Each domain is mutually exclusive by virtue of distinct prefixes.

    /// @dev Domain prefix for capability tokens minted by `PermissionToken`.
    bytes internal constant DOMAIN_PERMISSION = "perm:";

    /// @dev Domain prefix for strategy P&L tokens minted by `StrategyLedger`.
    bytes internal constant DOMAIN_STRATEGY_LEDGER = "strategy:";

    /// @dev Domain prefix for sponsorship-pool credits (F-14 multi-pool paymaster).
    bytes internal constant DOMAIN_PAYMASTER_POOL = "pool:";

    /// @dev Domain prefix for in-flight collateral receipts (F-23 L2).
    bytes internal constant DOMAIN_INFLIGHT = "inflight:";

    /// @notice Compute a permission token ID for a given (target, selector) pair.
    /// @dev    Used by `PermissionToken.grant` / `revoke` / `hasPermission` to
    ///         tag an ERC-6909 token ID domain-uniquely. Domain prefix
    ///         `"perm:"` ensures no collision with the strategy / paymaster /
    ///         inflight ledgers that share the underlying ERC-6909 contract
    ///         family.
    /// @param  target    The contract whose `selector` is being permissioned.
    /// @param  selector  The 4-byte function selector permission applies to.
    /// @return id        keccak256(`"perm:"` || target || selector) cast to uint256.
    function permissionId(
        address target,
        bytes4 selector
    ) internal pure returns (uint256 id) {
        return uint256(keccak256(abi.encodePacked(DOMAIN_PERMISSION, target, selector)));
    }

    /// @notice Compute a strategy P&L sub-ledger ID for a strategy tag.
    /// @dev    Used by `StrategyLedger.recordProfit` to mint balance against
    ///         a specific strategy bucket. Domain prefix `"strategy:"`
    ///         segregates from permission / paymaster / inflight IDs.
    /// @param  strategyTag  Caller-chosen strategy identifier (e.g.,
    ///                      `keccak256("matchInternal")`).
    /// @return id           keccak256(`"strategy:"` || tag) cast to uint256.
    function strategyId(
        bytes32 strategyTag
    ) internal pure returns (uint256 id) {
        return uint256(keccak256(abi.encodePacked(DOMAIN_STRATEGY_LEDGER, strategyTag)));
    }

    /// @notice Compute a paymaster pool ID for a pool tag.
    /// @dev    Reserved for the F-14 multi-pool paymaster extension; not
    ///         currently consumed by `MevPaymaster` (single-budget shape).
    ///         Domain prefix `"pool:"` keeps it isolated.
    /// @param  poolTag  Caller-chosen sponsorship-pool identifier.
    /// @return id       keccak256(`"pool:"` || tag) cast to uint256.
    function paymasterPoolId(
        bytes32 poolTag
    ) internal pure returns (uint256 id) {
        return uint256(keccak256(abi.encodePacked(DOMAIN_PAYMASTER_POOL, poolTag)));
    }

    /// @notice Compute an in-flight collateral receipt ID for an asset (F-23 L2).
    /// @dev    Reserved for the F-23 stuck-fund invariant. Domain prefix
    ///         `"inflight:"` segregates from the other ledgers.
    /// @param  asset  ERC-20 / native sentinel (`address(0)` for ETH).
    /// @return id     keccak256(`"inflight:"` || asset) cast to uint256.
    function inflightId(
        address asset
    ) internal pure returns (uint256 id) {
        return uint256(keccak256(abi.encodePacked(DOMAIN_INFLIGHT, asset)));
    }

    // @dev no EIP-7939 CLZ opportunities — only constant-time keccak256
    //      and abi.encodePacked operations.
}
