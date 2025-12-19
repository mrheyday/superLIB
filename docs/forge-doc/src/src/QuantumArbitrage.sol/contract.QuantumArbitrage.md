# QuantumArbitrage
[Git Source](https://github.com/example/superlib-arbitrage-protocol/blob/95c67768e2bfb00fae071b9d9bbef75272ead523/src/QuantumArbitrage.sol)

**Inherits:**
Auth, ReentrancyGuard

**Title:**
QuantumArbitrage

Orchestrates flash loan and risk engines with timelock-protected updates

Uses Superlib Auth for role-based access control


## State Variables
### ENGINE_UPDATE_TIMELOCK

```solidity
uint256 public constant ENGINE_UPDATE_TIMELOCK = 24 hours
```


### flashLoanEngine

```solidity
address public flashLoanEngine
```


### riskEngine

```solidity
address public riskEngine
```


### pendingFlashLoanEngine

```solidity
PendingUpdate public pendingFlashLoanEngine
```


### pendingRiskEngine

```solidity
PendingUpdate public pendingRiskEngine
```


### minRiskScore

```solidity
uint256 public minRiskScore = 30
```


### maxExecutionsPerBlock

```solidity
uint256 public maxExecutionsPerBlock = 5
```


### blockExecutionCount

```solidity
mapping(uint256 => uint256) public blockExecutionCount
```


## Functions
### constructor


```solidity
constructor(
    address _owner,
    Authority _authority,
    address _flashLoanEngine,
    address _riskEngine
) Auth(_owner, _authority);
```

### queueFlashLoanEngineUpdate


```solidity
function queueFlashLoanEngineUpdate(
    address newEngine
) external requiresAuth;
```

### executeFlashLoanEngineUpdate


```solidity
function executeFlashLoanEngineUpdate() external requiresAuth;
```

### queueRiskEngineUpdate


```solidity
function queueRiskEngineUpdate(
    address newEngine
) external requiresAuth;
```

### executeRiskEngineUpdate


```solidity
function executeRiskEngineUpdate() external requiresAuth;
```

### cancelPendingFlashLoanUpdate


```solidity
function cancelPendingFlashLoanUpdate() external requiresAuth;
```

### cancelPendingRiskUpdate


```solidity
function cancelPendingRiskUpdate() external requiresAuth;
```

### executeArbitrage


```solidity
function executeArbitrage(
    bytes calldata executionData
) external nonReentrant requiresAuth returns (bool);
```

### setMinRiskScore


```solidity
function setMinRiskScore(
    uint256 newScore
) external requiresAuth;
```

### setMaxExecutionsPerBlock


```solidity
function setMaxExecutionsPerBlock(
    uint256 newMax
) external requiresAuth;
```

### getPendingFlashLoanUpdate


```solidity
function getPendingFlashLoanUpdate() external view returns (address newEngine, uint256 executeAfter, bool exists);
```

### getPendingRiskUpdate


```solidity
function getPendingRiskUpdate() external view returns (address newEngine, uint256 executeAfter, bool exists);
```

### getRemainingExecutions


```solidity
function getRemainingExecutions() external view returns (uint256);
```

## Events
### FlashLoanEngineUpdateQueued

```solidity
event FlashLoanEngineUpdateQueued(address indexed newEngine, uint256 executeAfter);
```

### FlashLoanEngineUpdated

```solidity
event FlashLoanEngineUpdated(address indexed oldEngine, address indexed newEngine);
```

### RiskEngineUpdateQueued

```solidity
event RiskEngineUpdateQueued(address indexed newEngine, uint256 executeAfter);
```

### RiskEngineUpdated

```solidity
event RiskEngineUpdated(address indexed oldEngine, address indexed newEngine);
```

### UpdateCancelled

```solidity
event UpdateCancelled(string engineType);
```

### ArbitrageExecuted

```solidity
event ArbitrageExecuted(address indexed executor, uint256 riskScore, uint256 blockNumber);
```

### MinRiskScoreUpdated

```solidity
event MinRiskScoreUpdated(uint256 oldScore, uint256 newScore);
```

### MaxExecutionsUpdated

```solidity
event MaxExecutionsUpdated(uint256 oldMax, uint256 newMax);
```

## Errors
### TimelockActive

```solidity
error TimelockActive(uint256 executeAfter, uint256 currentTime);
```

### NoPendingUpdate

```solidity
error NoPendingUpdate();
```

### ZeroAddress

```solidity
error ZeroAddress();
```

### RiskScoreTooLow

```solidity
error RiskScoreTooLow(uint256 score, uint256 required);
```

### BlockExecutionLimitReached

```solidity
error BlockExecutionLimitReached(uint256 current, uint256 max);
```

### ExecutionFailed

```solidity
error ExecutionFailed();
```

## Structs
### PendingUpdate

```solidity
struct PendingUpdate {
    address newEngine;
    uint256 executeAfter;
    bool exists;
}
```

