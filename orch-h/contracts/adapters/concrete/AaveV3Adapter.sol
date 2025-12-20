// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../IFlashLender.sol";

/// @title Aave V3 Flash Loan Adapter (Skeleton)
contract AaveV3Adapter is IFlashLender {
    address public immutable pool;
    address public immutable executor;

    constructor(address _pool, address _executor) {
        pool = _pool;
        executor = _executor;
    }

    function flashBorrow(
        address asset,
        uint256 amount,
        bytes calldata data
    ) external override {
        require(msg.sender == executor, "ONLY_EXECUTOR");
        // Call Aave V3 pool.flashLoanSimple(...)
        // Skeleton only
    }

    function flashRepay(
        address asset,
        uint256 amount
    ) external override {
        require(msg.sender == executor, "ONLY_EXECUTOR");
        // Transfer asset back to pool
        // Skeleton only
    }
}
