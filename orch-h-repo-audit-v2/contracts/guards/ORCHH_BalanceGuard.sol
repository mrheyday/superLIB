// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IERC20 { function balanceOf(address) external view returns (uint256); }

library ORCHH_BalanceGuard {
    error BalanceMismatch();

    struct Snapshot { address asset; uint256 balance; }

    function snapshot(address asset, address holder) internal view returns (Snapshot memory) {
        return Snapshot({ asset: asset, balance: IERC20(asset).balanceOf(holder) });
    }

    function assertUnchanged(Snapshot memory snap, address holder) internal view {
        if (IERC20(snap.asset).balanceOf(holder) != snap.balance) revert BalanceMismatch();
    }
}
