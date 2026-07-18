// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";

/// @title LibSlippage — Slippage and TWAP deviation guards
/// @notice Enforces minimum output and optional TWAP sanity check
/// @dev All pure math — no storage reads in the hot path
library LibSlippage {
    using FixedPointMathLib for uint256;

    // ═══════════════════════════════════════════════════════════════
    //                          ERRORS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Output amount is below the minimum threshold
    error SlippageExceeded(uint256 amountOut, uint256 minOut);

    /// @notice Arbitrage is not profitable after fees
    error NoProfit(uint256 repayAmount, uint256 balance);

    /// @notice Price deviation exceeds max allowed basis-point drift from TWAP
    error TWAPDeviation(uint256 deviation, uint256 maxDeviation);

    // ═══════════════════════════════════════════════════════════════
    //                          CONSTANTS
    // ═══════════════════════════════════════════════════════════════

    /// @dev Basis point denominator
    uint256 internal constant BPS = 10_000;

    /// @dev Default max TWAP deviation: 500 bps = 5%
    uint256 internal constant DEFAULT_MAX_TWAP_DEVIATION_BPS = 500;

    /// @dev Absolute max TWAP deviation: 2000 bps = 20%
    uint256 internal constant ABSOLUTE_MAX_TWAP_DEVIATION_BPS = 2000;

    // ═══════════════════════════════════════════════════════════════
    //                          FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    /// @notice Check that amountOut >= minOut, revert with rich error otherwise
    /// @param amountOut Actual amount received
    /// @param minOut Minimum acceptable amount
    function enforceMinOut(uint256 amountOut, uint256 minOut) internal pure {
        if (amountOut < minOut) {
            revert SlippageExceeded(amountOut, minOut);
        }
    }

    /// @notice Compute minOut from amountIn with slippage tolerance
    /// @param amountIn Input amount
    /// @param slippageBps Slippage tolerance in basis points (e.g. 50 = 0.5%)
    /// @return minOut Minimum acceptable output
    function computeMinOut(uint256 amountIn, uint256 slippageBps) internal pure returns (uint256 minOut) {
        if (slippageBps >= BPS) revert SlippageExceeded(0, amountIn); // 100% slippage = nonsense
        minOut = amountIn.mulDiv(BPS - slippageBps, BPS);
    }

    /// @notice Validate spot price against TWAP reference
    /// @dev Reverts if |spotPrice - twapPrice| / twapPrice > maxDeviationBps
    /// @param spotPrice Current spot price (any scale, must match twapPrice)
    /// @param twapPrice TWAP reference price (same scale as spotPrice)
    /// @param maxDeviationBps Maximum deviation in basis points
    function enforceTWAP(uint256 spotPrice, uint256 twapPrice, uint256 maxDeviationBps) internal pure {
        if (twapPrice == 0) return; // Skip TWAP check if no reference provided
        if (maxDeviationBps > ABSOLUTE_MAX_TWAP_DEVIATION_BPS) {
            maxDeviationBps = ABSOLUTE_MAX_TWAP_DEVIATION_BPS;
        }

        // |spot - twap| * BPS / twap
        uint256 deviation;
        if (spotPrice > twapPrice) {
            deviation = (spotPrice - twapPrice).mulDiv(BPS, twapPrice);
        } else {
            deviation = (twapPrice - spotPrice).mulDiv(BPS, twapPrice);
        }

        if (deviation > maxDeviationBps) {
            revert TWAPDeviation(deviation, maxDeviationBps);
        }
    }

    /// @notice Compute effective price from amounts (tokenOut per tokenIn, scaled by 1e18)
    /// @param amountIn Input amount
    /// @param amountOut Output amount
    /// @return price Price in 1e18 scale
    function effectivePrice(uint256 amountIn, uint256 amountOut) internal pure returns (uint256 price) {
        if (amountIn == 0) return 0;
        price = amountOut.mulDiv(1e18, amountIn);
    }

    /// @notice Compute profit after flash loan repayment, with safety margin
    /// @param balance Current token balance
    /// @param repayAmount Amount owed (principal + fee)
    /// @param minProfitBps Minimum profit in bps of the borrowed amount
    /// @param borrowAmount Original borrowed amount (for bps calculation)
    /// @return profit Net profit after repayment
    function computeProfit(
        uint256 balance,
        uint256 repayAmount,
        uint256 minProfitBps,
        uint256 borrowAmount
    )
        internal
        pure
        returns (uint256 profit)
    {
        if (balance <= repayAmount) revert NoProfit(repayAmount, balance);
        profit = balance - repayAmount;

        // Enforce minimum profit threshold relative to borrow size
        if (minProfitBps > 0 && borrowAmount > 0) {
            uint256 minProfit = borrowAmount.mulDiv(minProfitBps, BPS);
            if (profit < minProfit) revert NoProfit(repayAmount, balance);
        }
    }

    /// @notice Compute flash loan repayment amount
    /// @param amount Borrowed amount
    /// @param feeBps Fee in basis points (e.g. 5 = 0.05% for Aave, 0 for Balancer)
    /// @return repayAmount Amount to repay (principal + fee)
    function computeRepayment(uint256 amount, uint256 feeBps) internal pure returns (uint256 repayAmount) {
        repayAmount = amount + amount.mulDiv(feeBps, BPS);
    }
}
