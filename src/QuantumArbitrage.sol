// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Auth, Authority} from "superlib/auth/Auth.sol";
import {ReentrancyGuard} from "superlib/security/ReentrancyLib.sol";

/// @title QuantumArbitrage
/// @notice Orchestrates flash loan and risk engines with timelock-protected updates
/// @dev Uses Superlib Auth for role-based access control
contract QuantumArbitrage is Auth, ReentrancyGuard {

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant ENGINE_UPDATE_TIMELOCK = 24 hours;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    struct PendingUpdate {
        address newEngine;
        uint256 executeAfter;
        bool exists;
    }

    address public flashLoanEngine;
    address public riskEngine;

    PendingUpdate public pendingFlashLoanEngine;
    PendingUpdate public pendingRiskEngine;

    uint256 public minRiskScore = 30;
    uint256 public maxExecutionsPerBlock = 5;
    mapping(uint256 => uint256) public blockExecutionCount;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event FlashLoanEngineUpdateQueued(address indexed newEngine, uint256 executeAfter);
    event FlashLoanEngineUpdated(address indexed oldEngine, address indexed newEngine);
    event RiskEngineUpdateQueued(address indexed newEngine, uint256 executeAfter);
    event RiskEngineUpdated(address indexed oldEngine, address indexed newEngine);
    event UpdateCancelled(string engineType);
    event ArbitrageExecuted(address indexed executor, uint256 riskScore, uint256 blockNumber);
    event MinRiskScoreUpdated(uint256 oldScore, uint256 newScore);
    event MaxExecutionsUpdated(uint256 oldMax, uint256 newMax);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error TimelockActive(uint256 executeAfter, uint256 currentTime);
    error NoPendingUpdate();
    error ZeroAddress();
    error RiskScoreTooLow(uint256 score, uint256 required);
    error BlockExecutionLimitReached(uint256 current, uint256 max);
    error ExecutionFailed();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _owner,
        Authority _authority,
        address _flashLoanEngine,
        address _riskEngine
    ) Auth(_owner, _authority) {
        if (_flashLoanEngine == address(0) || _riskEngine == address(0)) revert ZeroAddress();
        flashLoanEngine = _flashLoanEngine;
        riskEngine = _riskEngine;
    }

    /*//////////////////////////////////////////////////////////////
                      TIMELOCK ENGINE UPDATES
    //////////////////////////////////////////////////////////////*/

    function queueFlashLoanEngineUpdate(
        address newEngine
    ) external requiresAuth {
        if (newEngine == address(0)) revert ZeroAddress();

        uint256 executeAfter = block.timestamp + ENGINE_UPDATE_TIMELOCK;
        pendingFlashLoanEngine = PendingUpdate({newEngine: newEngine, executeAfter: executeAfter, exists: true});

        emit FlashLoanEngineUpdateQueued(newEngine, executeAfter);
    }

    function executeFlashLoanEngineUpdate() external requiresAuth {
        PendingUpdate memory pending = pendingFlashLoanEngine;
        if (!pending.exists) revert NoPendingUpdate();
        if (block.timestamp < pending.executeAfter) {
            revert TimelockActive(pending.executeAfter, block.timestamp);
        }

        address oldEngine = flashLoanEngine;
        flashLoanEngine = pending.newEngine;
        delete pendingFlashLoanEngine;

        emit FlashLoanEngineUpdated(oldEngine, pending.newEngine);
    }

    function queueRiskEngineUpdate(
        address newEngine
    ) external requiresAuth {
        if (newEngine == address(0)) revert ZeroAddress();

        uint256 executeAfter = block.timestamp + ENGINE_UPDATE_TIMELOCK;
        pendingRiskEngine = PendingUpdate({newEngine: newEngine, executeAfter: executeAfter, exists: true});

        emit RiskEngineUpdateQueued(newEngine, executeAfter);
    }

    function executeRiskEngineUpdate() external requiresAuth {
        PendingUpdate memory pending = pendingRiskEngine;
        if (!pending.exists) revert NoPendingUpdate();
        if (block.timestamp < pending.executeAfter) {
            revert TimelockActive(pending.executeAfter, block.timestamp);
        }

        address oldEngine = riskEngine;
        riskEngine = pending.newEngine;
        delete pendingRiskEngine;

        emit RiskEngineUpdated(oldEngine, pending.newEngine);
    }

    function cancelPendingFlashLoanUpdate() external requiresAuth {
        if (!pendingFlashLoanEngine.exists) revert NoPendingUpdate();
        delete pendingFlashLoanEngine;
        emit UpdateCancelled("flashLoanEngine");
    }

    function cancelPendingRiskUpdate() external requiresAuth {
        if (!pendingRiskEngine.exists) revert NoPendingUpdate();
        delete pendingRiskEngine;
        emit UpdateCancelled("riskEngine");
    }

    /*//////////////////////////////////////////////////////////////
                        ARBITRAGE EXECUTION
    //////////////////////////////////////////////////////////////*/

    function executeArbitrage(
        bytes calldata executionData
    ) external nonReentrant requiresAuth returns (bool) {
        // Check block execution limit
        uint256 currentCount = blockExecutionCount[block.number];
        if (currentCount >= maxExecutionsPerBlock) {
            revert BlockExecutionLimitReached(currentCount, maxExecutionsPerBlock);
        }
        blockExecutionCount[block.number]++;

        // Get risk score from risk engine
        (bool riskSuccess, bytes memory riskResult) = riskEngine.staticcall(
            abi.encodeWithSignature("evaluate(address,uint256,uint256)", msg.sender, 0, block.timestamp)
        );

        uint256 riskScore = 50; // Default if call fails
        if (riskSuccess && riskResult.length >= 32) {
            riskScore = abi.decode(riskResult, (uint256));
        }

        if (riskScore < minRiskScore) revert RiskScoreTooLow(riskScore, minRiskScore);

        // Execute through flash loan engine
        (bool success,) = flashLoanEngine.call(executionData);
        if (!success) revert ExecutionFailed();

        emit ArbitrageExecuted(msg.sender, riskScore, block.number);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                         CONFIG MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function setMinRiskScore(
        uint256 newScore
    ) external requiresAuth {
        emit MinRiskScoreUpdated(minRiskScore, newScore);
        minRiskScore = newScore;
    }

    function setMaxExecutionsPerBlock(
        uint256 newMax
    ) external requiresAuth {
        emit MaxExecutionsUpdated(maxExecutionsPerBlock, newMax);
        maxExecutionsPerBlock = newMax;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getPendingFlashLoanUpdate() external view returns (address newEngine, uint256 executeAfter, bool exists) {
        PendingUpdate memory p = pendingFlashLoanEngine;
        return (p.newEngine, p.executeAfter, p.exists);
    }

    function getPendingRiskUpdate() external view returns (address newEngine, uint256 executeAfter, bool exists) {
        PendingUpdate memory p = pendingRiskEngine;
        return (p.newEngine, p.executeAfter, p.exists);
    }

    function getRemainingExecutions() external view returns (uint256) {
        uint256 current = blockExecutionCount[block.number];
        return current >= maxExecutionsPerBlock ? 0 : maxExecutionsPerBlock - current;
    }

}
