// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title ORCH-H Flash Lender Adapter Interface
/// @notice Uniform interface for all flash loan providers
interface IFlashLender {
    /// @notice Initiate a flash loan
    /// @param asset The asset to borrow
    /// @param amount The amount to borrow
    /// @param data Arbitrary data forwarded to executor
    function flashBorrow(
        address asset,
        uint256 amount,
        bytes calldata data
    ) external;

    /// @notice Called by executor to repay the loan
    function flashRepay(
        address asset,
        uint256 amount
    ) external;
}
