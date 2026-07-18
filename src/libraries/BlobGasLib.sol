// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title BlobGasLib — EIP-7516 Blob Base Fee Pricing Library
/// @notice Provides access to the blob base fee via the BLOBBASEFEE opcode (0x4a, 2 gas).
///         Enables L2 MEV profitability calculations by factoring in data availability costs.
/// @dev EIP-7516 (Final/Live on Dencun): BLOBBASEFEE returns the blob base fee of the current
///      block, allowing contracts to price data availability costs for L2 settlement.
///
///      EIP-7918 (Live on Fusaka): Blob base fee floor — pins a proportional reserve price
///      under every blob. When the reserve exceeds the nominal blob base fee, the fee
///      adjustment algorithm treats the block as over-target, preventing the blob fee
///      from spiraling down to 1 wei during low-demand periods.
///
///      MEV applications:
///        - Calculate DA cost of posting L2 execution proofs
///        - Determine if L2 MEV is profitable after DA overhead
///        - Dynamic gas bidding based on blob market conditions
///        - Account for blob fee floor when estimating minimum DA costs
///
/// @custom:eip EIP-7516: BLOBBASEFEE opcode
/// @custom:eip EIP-7918: Blob base fee floor (Fusaka)
/// @custom:opcode 0x4a — pushes blob base fee (uint256), 2 gas
library BlobGasLib {
    /// @dev Target blob gas per block (EIP-4844)
    uint256 internal constant TARGET_BLOB_GAS_PER_BLOCK = 393216; // 3 blobs * 131072

    /// @dev Max blob gas per block (EIP-4844)
    uint256 internal constant MAX_BLOB_GAS_PER_BLOCK = 786432; // 6 blobs * 131072

    /// @dev Gas per blob (EIP-4844)
    uint256 internal constant GAS_PER_BLOB = 131072;

    /// @dev Minimum blob base fee (1 wei)
    uint256 internal constant MIN_BLOB_BASE_FEE = 1;

    /// @dev EIP-7918: Blob fee floor — proportional reserve price per blob
    ///      The floor prevents blob fees from collapsing to 1 wei during low demand.
    ///      Value: approximate minimum viable fee (~21 gwei baseline, aligned with
    ///      Fusaka parameterization). Rust engine should query the live floor from
    ///      the CL for exact value; this constant is a conservative lower bound.
    /// @custom:eip EIP-7918: Blob base fee floor
    uint256 internal constant BLOB_FEE_FLOOR = 21 gwei;

    /// @dev EIP-7918: Target blob count per block (Fusaka updated from 3 to 6)
    uint256 internal constant TARGET_BLOB_COUNT = 6;

    /// @dev EIP-7918: Max blob count per block (Fusaka updated from 6 to 9)
    uint256 internal constant MAX_BLOB_COUNT = 9;

    /// @notice Get the current blob base fee via BLOBBASEFEE opcode (0x4a)
    /// @dev Returns 0 on chains without EIP-7516 support (pre-Dencun)
    /// @return fee The blob base fee in wei
    function getBlobBaseFee() internal view returns (uint256 fee) {
        assembly ("memory-safe") {
            fee := blobbasefee()
        }
    }

    /// @notice Calculate the data availability cost for posting N blobs
    /// @param numBlobs Number of blobs to post
    /// @return cost Total DA cost in wei
    function calculateDACost(uint256 numBlobs) internal view returns (uint256 cost) {
        uint256 fee = getBlobBaseFee();
        cost = fee * GAS_PER_BLOB * numBlobs;
    }

    /// @notice Check if an MEV opportunity is profitable after DA costs
    /// @dev Used for L2 MEV: profit must exceed DA cost + execution gas
    /// @param grossProfit Expected profit from MEV execution
    /// @param numBlobs Number of blobs needed for DA
    /// @param executionGasCost Gas cost of on-chain execution (in wei)
    /// @return profitable True if net profit is positive
    /// @return netProfit The net profit after DA and execution costs
    function isProfitableAfterDA(
        uint256 grossProfit,
        uint256 numBlobs,
        uint256 executionGasCost
    )
        internal
        view
        returns (bool profitable, uint256 netProfit)
    {
        uint256 daCost = calculateDACost(numBlobs);
        uint256 totalCost = daCost + executionGasCost;

        if (grossProfit > totalCost) {
            profitable = true;
            netProfit = grossProfit - totalCost;
        }
    }

    /// @notice Estimate optimal blob count for a given data size
    /// @param dataBytes Size of data to post (in bytes)
    /// @return numBlobs Number of blobs required (each ~128 KB usable)
    /// @dev Returns 0 for 0 bytes — no data means no blobs needed.
    ///      This avoids false negatives in isProfitableAfterDA() by not charging
    ///      a phantom blob's DA cost for zero-byte submissions.
    function estimateBlobCount(uint256 dataBytes) internal pure returns (uint256 numBlobs) {
        // Each blob holds ~128 KB (131072 bytes) of data
        // Using 126976 bytes usable (after field element encoding overhead)
        if (dataBytes == 0) return 0;
        uint256 usablePerBlob = 126976;
        numBlobs = (dataBytes + usablePerBlob - 1) / usablePerBlob;
    }

    /// @notice Get blob gas price ratio vs regular gas for cost comparison
    /// @dev Useful for deciding between calldata vs blob DA posting
    /// @return ratio Blob gas price as a percentage of regular gas price (scaled by 1e18)
    function blobToRegularGasRatio() internal view returns (uint256 ratio) {
        uint256 blobFee = getBlobBaseFee();
        if (blobFee == 0 || tx.gasprice == 0) return 0;
        // ratio = (blobFee * 1e18) / tx.gasprice
        ratio = (blobFee * 1e18) / tx.gasprice;
    }

    // ═══════════════════════════════════════════════════════════════
    //              EIP-7918: BLOB FEE FLOOR SUPPORT
    // ═══════════════════════════════════════════════════════════════

    /// @notice Get the effective blob fee, accounting for the EIP-7918 floor
    /// @dev Post-Fusaka, the blob fee is guaranteed to be at least BLOB_FEE_FLOOR.
    ///      This function returns max(blobbasefee(), BLOB_FEE_FLOOR) for accurate
    ///      DA cost estimation on Fusaka+ chains.
    /// @return fee The effective blob fee (never below BLOB_FEE_FLOOR)
    function getEffectiveBlobFee() internal view returns (uint256 fee) {
        fee = getBlobBaseFee();
        if (fee < BLOB_FEE_FLOOR) {
            fee = BLOB_FEE_FLOOR;
        }
    }

    /// @notice Calculate DA cost using the EIP-7918 floor-aware blob fee
    /// @dev Like calculateDACost() but uses the effective fee (max of actual vs floor)
    /// @param numBlobs Number of blobs to post
    /// @return cost Total DA cost in wei (with floor applied)
    function calculateDACostWithFloor(uint256 numBlobs) internal view returns (uint256 cost) {
        uint256 fee = getEffectiveBlobFee();
        cost = fee * GAS_PER_BLOB * numBlobs;
    }

    /// @notice Check MEV profitability with EIP-7918 floor-aware DA costs
    /// @dev More conservative than isProfitableAfterDA() — accounts for the blob fee floor.
    ///      Recommended for post-Fusaka profitability checks.
    /// @param grossProfit Expected profit from MEV execution
    /// @param numBlobs Number of blobs needed for DA
    /// @param executionGasCost Gas cost of on-chain execution (in wei)
    /// @return profitable True if net profit is positive after floor-adjusted DA costs
    /// @return netProfit The net profit after floor-adjusted DA and execution costs
    function isProfitableAfterDAWithFloor(
        uint256 grossProfit,
        uint256 numBlobs,
        uint256 executionGasCost
    )
        internal
        view
        returns (bool profitable, uint256 netProfit)
    {
        uint256 daCost = calculateDACostWithFloor(numBlobs);
        uint256 totalCost = daCost + executionGasCost;

        if (grossProfit > totalCost) {
            profitable = true;
            netProfit = grossProfit - totalCost;
        }
    }

    /// @notice Get the minimum possible DA cost for a given blob count
    /// @dev Pure function — uses the BLOB_FEE_FLOOR constant for worst-case estimation.
    ///      Useful for Rust engine to set minimum profitability thresholds.
    /// @param numBlobs Number of blobs
    /// @return minCost Minimum DA cost (floor × GAS_PER_BLOB × numBlobs)
    function minimumDACost(uint256 numBlobs) internal pure returns (uint256 minCost) {
        minCost = BLOB_FEE_FLOOR * GAS_PER_BLOB * numBlobs;
    }
}

