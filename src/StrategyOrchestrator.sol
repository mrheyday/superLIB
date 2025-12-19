// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Auth, Authority} from "superlib/auth/Auth.sol";

/// @title StrategyOrchestrator
/// @notice Manages arbitrage strategies with bounded arrays and pagination
/// @dev Uses Superlib Auth for role-based access control
contract StrategyOrchestrator is Auth {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MAX_STRATEGIES = 100;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    enum StrategyType {
        TriangularArbitrage,
        CrossChainArbitrage,
        StatisticalArbitrage,
        VolatilityArbitrage,
        LiquidityArbitrage,
        MEVArbitrage
    }

    struct StrategyConfig {
        bytes32 strategyId;
        StrategyType strategyType;
        uint256 capitalAllocation;
        uint256 riskTolerance;
        uint256 profitTarget;
        uint256 stopLoss;
        bool active;
        uint256 createdAt;
        uint256 lastExecutedAt;
    }

    mapping(bytes32 => StrategyConfig) public strategies;
    bytes32[] public strategyIds;
    mapping(StrategyType => uint256) public strategyTypeCount;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event StrategyAdded(bytes32 indexed strategyId, StrategyType strategyType, uint256 capitalAllocation);
    event StrategyRemoved(bytes32 indexed strategyId);
    event StrategyUpdated(bytes32 indexed strategyId, uint256 capitalAllocation, uint256 riskTolerance);
    event StrategyExecuted(bytes32 indexed strategyId, uint256 profit, uint256 timestamp);
    event StrategyToggled(bytes32 indexed strategyId, bool active);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error MaxStrategiesReached(uint256 current, uint256 max);
    error StrategyNotFound(bytes32 strategyId);
    error StrategyAlreadyExists(bytes32 strategyId);
    error InvalidCapitalAllocation();
    error InvalidRiskTolerance();
    error StrategyNotActive(bytes32 strategyId);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _owner,
        Authority _authority
    ) Auth(_owner, _authority) {}

    /*//////////////////////////////////////////////////////////////
                        STRATEGY MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function addStrategy(
        bytes32 strategyId,
        StrategyType strategyType,
        uint256 capitalAllocation,
        uint256 riskTolerance,
        uint256 profitTarget,
        uint256 stopLoss
    ) external requiresAuth {
        if (strategyIds.length >= MAX_STRATEGIES) {
            revert MaxStrategiesReached(strategyIds.length, MAX_STRATEGIES);
        }
        if (strategies[strategyId].createdAt != 0) {
            revert StrategyAlreadyExists(strategyId);
        }
        if (capitalAllocation == 0) revert InvalidCapitalAllocation();
        if (riskTolerance > 100) revert InvalidRiskTolerance();

        strategies[strategyId] = StrategyConfig({
            strategyId: strategyId,
            strategyType: strategyType,
            capitalAllocation: capitalAllocation,
            riskTolerance: riskTolerance,
            profitTarget: profitTarget,
            stopLoss: stopLoss,
            active: true,
            createdAt: block.timestamp,
            lastExecutedAt: 0
        });

        strategyIds.push(strategyId);
        strategyTypeCount[strategyType]++;

        emit StrategyAdded(strategyId, strategyType, capitalAllocation);
    }

    function removeStrategy(
        bytes32 strategyId
    ) external requiresAuth {
        StrategyConfig memory strategy = strategies[strategyId];
        if (strategy.createdAt == 0) revert StrategyNotFound(strategyId);

        // Safe decrement with underflow guard
        uint256 currentCount = strategyTypeCount[strategy.strategyType];
        if (currentCount > 0) {
            strategyTypeCount[strategy.strategyType] = currentCount - 1;
        }
        
        delete strategies[strategyId];

        // Remove from array
        for (uint256 i = 0; i < strategyIds.length; i++) {
            if (strategyIds[i] == strategyId) {
                strategyIds[i] = strategyIds[strategyIds.length - 1];
                strategyIds.pop();
                break;
            }
        }

        emit StrategyRemoved(strategyId);
    }

    function updateStrategy(
        bytes32 strategyId,
        uint256 capitalAllocation,
        uint256 riskTolerance,
        uint256 profitTarget,
        uint256 stopLoss
    ) external requiresAuth {
        if (strategies[strategyId].createdAt == 0) revert StrategyNotFound(strategyId);
        if (capitalAllocation == 0) revert InvalidCapitalAllocation();
        if (riskTolerance > 100) revert InvalidRiskTolerance();

        StrategyConfig storage strategy = strategies[strategyId];
        strategy.capitalAllocation = capitalAllocation;
        strategy.riskTolerance = riskTolerance;
        strategy.profitTarget = profitTarget;
        strategy.stopLoss = stopLoss;

        emit StrategyUpdated(strategyId, capitalAllocation, riskTolerance);
    }

    function toggleStrategy(
        bytes32 strategyId,
        bool active
    ) external requiresAuth {
        if (strategies[strategyId].createdAt == 0) revert StrategyNotFound(strategyId);
        strategies[strategyId].active = active;
        emit StrategyToggled(strategyId, active);
    }

    function executeStrategyFlow(
        bytes32 strategyId
    ) external requiresAuth returns (bool) {
        StrategyConfig storage strategy = strategies[strategyId];
        if (strategy.createdAt == 0) revert StrategyNotFound(strategyId);
        if (!strategy.active) revert StrategyNotActive(strategyId);

        strategy.lastExecutedAt = block.timestamp;

        emit StrategyExecuted(strategyId, 0, block.timestamp);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getStrategy(
        bytes32 strategyId
    ) external view returns (StrategyConfig memory) {
        return strategies[strategyId];
    }

    function getStrategyCount() external view returns (uint256) {
        return strategyIds.length;
    }

    function getStrategiesPaginated(
        uint256 offset,
        uint256 limit
    ) external view returns (StrategyConfig[] memory result, uint256 total) {
        total = strategyIds.length;
        if (offset >= total) {
            return (new StrategyConfig[](0), total);
        }

        uint256 remaining = total - offset;
        uint256 count = remaining < limit ? remaining : limit;
        result = new StrategyConfig[](count);

        for (uint256 i = 0; i < count; i++) {
            result[i] = strategies[strategyIds[offset + i]];
        }
    }

    /// @notice Get paginated list of active strategies
    /// @param offset Starting index
    /// @param limit Maximum strategies to return
    /// @return strategies Array of active strategy IDs
    /// @return total Total number of active strategies
    function getActiveStrategies(
        uint256 offset,
        uint256 limit
    ) external view returns (bytes32[] memory, uint256 total) {
        // First pass: count active
        uint256 activeCount = 0;
        for (uint256 i = 0; i < strategyIds.length; i++) {
            if (strategies[strategyIds[i]].active) activeCount++;
        }
        total = activeCount;

        // Handle pagination bounds
        if (offset >= activeCount) {
            return (new bytes32[](0), total);
        }
        
        uint256 remaining = activeCount - offset;
        uint256 returnCount = remaining < limit ? remaining : limit;
        bytes32[] memory result = new bytes32[](returnCount);

        // Second pass: collect paginated results
        uint256 activeIndex = 0;
        uint256 resultIndex = 0;
        for (uint256 i = 0; i < strategyIds.length && resultIndex < returnCount; i++) {
            if (strategies[strategyIds[i]].active) {
                if (activeIndex >= offset) {
                    result[resultIndex++] = strategyIds[i];
                }
                activeIndex++;
            }
        }
        return (result, total);
    }

    /// @notice Get all active strategies (use with caution for large sets)
    /// @dev Consider using paginated version for production
    function getAllActiveStrategies() external view returns (bytes32[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < strategyIds.length; i++) {
            if (strategies[strategyIds[i]].active) activeCount++;
        }

        bytes32[] memory active = new bytes32[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < strategyIds.length; i++) {
            if (strategies[strategyIds[i]].active) {
                active[index++] = strategyIds[i];
            }
        }
        return active;
    }

    function getStrategiesByType(
        StrategyType strategyType
    ) external view returns (bytes32[] memory) {
        uint256 count = strategyTypeCount[strategyType];
        bytes32[] memory result = new bytes32[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < strategyIds.length && index < count; i++) {
            if (strategies[strategyIds[i]].strategyType == strategyType) {
                result[index++] = strategyIds[i];
            }
        }
        return result;
    }
}
