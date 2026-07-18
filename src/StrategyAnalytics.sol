// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Auth, Authority} from "superlib/auth/Auth.sol";

/// @title StrategyAnalytics
/// @notice Tracks execution metrics for arbitrage strategies
/// @dev Uses Superlib Auth for role-based access control
contract StrategyAnalytics is Auth {
    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    struct StrategyMetrics {
        uint256 totalTrades;
        uint256 successfulTrades;
        uint256 totalProfit;
        uint256 totalLoss;
        uint256 lastExecutionTime;
        uint256 avgExecutionTime;
    }

    mapping(bytes32 => StrategyMetrics) public strategyMetrics;
    mapping(address => uint256) public executorTradeCount;

    uint256 public totalProtocolProfit;
    uint256 public totalProtocolTrades;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event TradeRecorded(bytes32 indexed strategyId, bool success, uint256 profit, uint256 loss);
    event MetricsReset(bytes32 indexed strategyId);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error ZeroStrategyId();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, Authority _authority) Auth(_owner, _authority) {}

    /*//////////////////////////////////////////////////////////////
                         METRICS RECORDING
    //////////////////////////////////////////////////////////////*/

    function recordTrade(bytes32 strategyId, bool success, uint256 profit, uint256 loss, uint256 executionTime)
        external
        requiresAuth
    {
        if (strategyId == bytes32(0)) revert ZeroStrategyId();

        StrategyMetrics storage metrics = strategyMetrics[strategyId];

        metrics.totalTrades++;
        if (success) {
            metrics.successfulTrades++;
            metrics.totalProfit += profit;
            totalProtocolProfit += profit;
        } else {
            metrics.totalLoss += loss;
        }

        // Update average execution time
        if (metrics.avgExecutionTime == 0) {
            metrics.avgExecutionTime = executionTime;
        } else {
            metrics.avgExecutionTime = (metrics.avgExecutionTime + executionTime) / 2;
        }

        metrics.lastExecutionTime = block.timestamp;
        executorTradeCount[msg.sender]++;
        totalProtocolTrades++;

        emit TradeRecorded(strategyId, success, profit, loss);
    }

    function resetMetrics(bytes32 strategyId) external requiresAuth {
        delete strategyMetrics[strategyId];
        emit MetricsReset(strategyId);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getMetrics(bytes32 strategyId) external view returns (StrategyMetrics memory) {
        return strategyMetrics[strategyId];
    }

    function getSuccessRate(bytes32 strategyId) external view returns (uint256) {
        StrategyMetrics memory metrics = strategyMetrics[strategyId];
        if (metrics.totalTrades == 0) return 0;
        return (metrics.successfulTrades * 10_000) / metrics.totalTrades;
    }

    function getNetProfit(bytes32 strategyId) external view returns (int256) {
        StrategyMetrics memory metrics = strategyMetrics[strategyId];
        return int256(metrics.totalProfit) - int256(metrics.totalLoss);
    }

    function getProtocolStats() external view returns (uint256 trades, uint256 profit) {
        return (totalProtocolTrades, totalProtocolProfit);
    }
}
