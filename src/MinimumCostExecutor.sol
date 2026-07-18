// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Auth, Authority} from "superlib/auth/Auth.sol";
import {ReentrancyGuard} from "superlib/security/ReentrancyLib.sol";

/// @title MinimumCostExecutor
/// @notice Optimizes execution costs with gas price management
/// @dev Uses Superlib Auth for role-based access control
contract MinimumCostExecutor is Auth, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 public maxCostPercentage = 500; // 5% max cost of profit
    uint256 public defaultPriorityFee = 1 gwei;
    uint256 public maxGasPrice = 500 gwei;

    mapping(address => uint256) public executorGasRefunds;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ExecutionCompleted(address indexed executor, uint256 gasUsed, uint256 cost, uint256 profit);
    event MaxCostPercentageUpdated(uint256 oldValue, uint256 newValue);
    event DefaultPriorityFeeUpdated(uint256 oldValue, uint256 newValue);
    event MaxGasPriceUpdated(uint256 oldValue, uint256 newValue);
    event GasRefundClaimed(address indexed executor, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error CostExceedsLimit(uint256 cost, uint256 maxCost);
    error GasPriceTooHigh(uint256 gasPrice, uint256 maxGasPrice);
    error NoRefundAvailable();
    error ExecutionFailed();
    error InvalidPercentage();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, Authority _authority) Auth(_owner, _authority) {}

    /*//////////////////////////////////////////////////////////////
                        COST-OPTIMIZED EXECUTION
    //////////////////////////////////////////////////////////////*/

    function executeWithMinimumCost(address target, bytes calldata data, uint256 expectedProfit)
        external
        nonReentrant
        requiresAuth
        returns (bool success, bytes memory result)
    {
        uint256 gasStart = gasleft();

        // Check gas price
        if (tx.gasprice > maxGasPrice) revert GasPriceTooHigh(tx.gasprice, maxGasPrice);

        // Execute
        (success, result) = target.call(data);
        if (!success) revert ExecutionFailed();

        // Calculate cost
        uint256 gasUsed = gasStart - gasleft();
        uint256 cost = gasUsed * tx.gasprice;

        // Verify cost is within limits
        uint256 maxCost = (expectedProfit * maxCostPercentage) / 10_000;
        if (cost > maxCost) revert CostExceedsLimit(cost, maxCost);

        emit ExecutionCompleted(msg.sender, gasUsed, cost, expectedProfit);
    }

    /*//////////////////////////////////////////////////////////////
                         CONFIG MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function setMaxCostPercentage(uint256 newPercentage) external requiresAuth {
        if (newPercentage > 10_000) revert InvalidPercentage();
        emit MaxCostPercentageUpdated(maxCostPercentage, newPercentage);
        maxCostPercentage = newPercentage;
    }

    function setDefaultPriorityFee(uint256 newFee) external requiresAuth {
        emit DefaultPriorityFeeUpdated(defaultPriorityFee, newFee);
        defaultPriorityFee = newFee;
    }

    function setMaxGasPrice(uint256 newMaxGasPrice) external requiresAuth {
        emit MaxGasPriceUpdated(maxGasPrice, newMaxGasPrice);
        maxGasPrice = newMaxGasPrice;
    }

    function addGasRefund(address executor, uint256 amount) external requiresAuth {
        executorGasRefunds[executor] += amount;
    }

    function claimGasRefund() external nonReentrant {
        uint256 refund = executorGasRefunds[msg.sender];
        if (refund == 0) revert NoRefundAvailable();

        executorGasRefunds[msg.sender] = 0;
        payable(msg.sender).transfer(refund);

        emit GasRefundClaimed(msg.sender, refund);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function estimateCost(uint256 gasEstimate) external view returns (uint256) {
        return gasEstimate * (tx.gasprice + defaultPriorityFee);
    }

    function isGasPriceAcceptable() external view returns (bool) {
        return tx.gasprice <= maxGasPrice;
    }

    receive() external payable {}
}
