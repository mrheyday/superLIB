// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IFlashLender {
    function flashBorrow(address asset, uint256 amount, bytes calldata data) external;
    function flashRepay(address asset, uint256 amount) external;
}
