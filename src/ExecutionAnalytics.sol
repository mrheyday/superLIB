// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Auth, Authority} from "superlib/auth/Auth.sol";

/// @title ExecutionAnalytics
/// @notice Tracks execution-level analytics and gas metrics
/// @dev Uses Superlib Auth for role-based access control
contract ExecutionAnalytics is Auth {

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    struct ExecutionRecord {
        uint256 timestamp;
        uint256 gasUsed;
        uint256 gasPrice;
        uint256 profit;
        bool success;
    }

    mapping(bytes32 => ExecutionRecord[]) public executionHistory;
    mapping(address => uint256) public executorGasSpent;

    uint256 public totalExecutions;
    uint256 public totalGasUsed;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ExecutionRecorded(bytes32 indexed executionId, uint256 gasUsed, uint256 profit, bool success);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _owner,
        Authority _authority
    ) Auth(_owner, _authority) {}

    /*//////////////////////////////////////////////////////////////
                         ANALYTICS RECORDING
    //////////////////////////////////////////////////////////////*/

    function recordExecution(
        bytes32 executionId,
        uint256 gasUsed,
        uint256 gasPrice,
        uint256 profit,
        bool success
    ) external requiresAuth {
        executionHistory[executionId].push(
            ExecutionRecord({
                timestamp: block.timestamp, gasUsed: gasUsed, gasPrice: gasPrice, profit: profit, success: success
            })
        );

        executorGasSpent[msg.sender] += gasUsed * gasPrice;
        totalExecutions++;
        totalGasUsed += gasUsed;

        emit ExecutionRecorded(executionId, gasUsed, profit, success);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getExecutionHistory(
        bytes32 executionId
    ) external view returns (ExecutionRecord[] memory) {
        return executionHistory[executionId];
    }

    function getExecutionCount(
        bytes32 executionId
    ) external view returns (uint256) {
        return executionHistory[executionId].length;
    }

    function getAverageGasUsed(
        bytes32 executionId
    ) external view returns (uint256) {
        ExecutionRecord[] memory history = executionHistory[executionId];
        if (history.length == 0) return 0;

        uint256 total = 0;
        for (uint256 i = 0; i < history.length; i++) {
            total += history[i].gasUsed;
        }
        return total / history.length;
    }

    function getProtocolStats() external view returns (uint256 executions, uint256 gas) {
        return (totalExecutions, totalGasUsed);
    }

}
