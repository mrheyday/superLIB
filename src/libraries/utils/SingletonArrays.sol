// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title  SingletonArrays
/// @notice Helpers for wrapping a single value as a length-1 array.
/// @dev    Per `docs/architecture/05-EXECUTOR-CONTRACT-SPEC.md` §6.1, Aave V3 multi-asset
///         flash-loan calls accept arrays even for single-asset borrows (H2). These helpers
///         keep call sites clean and avoid one-off allocation boilerplate.
library SingletonArrays {
    /// @notice Wrap a single `address` as a length-1 `address[] memory`.
    /// @dev    Used by `Executor._triggerFlashLoan` Aave path so the H2
    ///         "always pass arrays even for a single asset" pattern stays
    ///         readable at call sites.
    /// @param  a  The address to wrap.
    /// @return r  Newly-allocated length-1 memory array containing `a`.
    function singleton(
        address a
    ) internal pure returns (address[] memory r) {
        r = new address[](1);
        r[0] = a;
    }

    /// @notice Wrap a single `uint256` as a length-1 `uint256[] memory`.
    /// @dev    Same H2 rationale as the address overload; used for Aave's
    ///         `amounts[]` and `interestRateModes[]` arguments.
    /// @param  v  The value to wrap.
    /// @return r  Newly-allocated length-1 memory array containing `v`.
    function singleton(
        uint256 v
    ) internal pure returns (uint256[] memory r) {
        r = new uint256[](1);
        r[0] = v;
    }

    /// @notice Wrap a single `bytes memory` as a length-1 `bytes[] memory`.
    /// @dev    Project-internal use today is dormant — kept for ABI-symmetric
    ///         dispatch in future entries that ferry per-asset userData.
    ///         Aderyn flagging this as "unused" is a future-phase reserve;
    ///         not dead code.
    /// @param  b  The bytes blob to wrap.
    /// @return r  Newly-allocated length-1 memory array containing `b`.
    function singleton(
        bytes memory b
    ) internal pure returns (bytes[] memory r) {
        r = new bytes[](1);
        r[0] = b;
    }

    // @dev no EIP-7939 CLZ opportunities — only constant-time array allocation.
}
