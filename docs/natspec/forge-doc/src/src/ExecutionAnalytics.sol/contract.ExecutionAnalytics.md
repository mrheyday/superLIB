# ExecutionAnalytics
[Git Source](https://github.com/example/superlib-arbitrage-protocol/blob/95c67768e2bfb00fae071b9d9bbef75272ead523/src/ExecutionAnalytics.sol)

**Inherits:**
Auth

**Title:**
ExecutionAnalytics

Tracks execution-level analytics and gas metrics

Uses Superlib Auth for role-based access control


## State Variables
### executionHistory

```solidity
mapping(bytes32 => ExecutionRecord[]) public executionHistory
```


### executorGasSpent

```solidity
mapping(address => uint256) public executorGasSpent
```


### totalExecutions

```solidity
uint256 public totalExecutions
```


### totalGasUsed

```solidity
uint256 public totalGasUsed
```


## Functions
### constructor


```solidity
constructor(
    address _owner,
    Authority _authority
) Auth(_owner, _authority);
```

### recordExecution


```solidity
function recordExecution(
    bytes32 executionId,
    uint256 gasUsed,
    uint256 gasPrice,
    uint256 profit,
    bool success
) external requiresAuth;
```

### getExecutionHistory


```solidity
function getExecutionHistory(
    bytes32 executionId
) external view returns (ExecutionRecord[] memory);
```

### getExecutionCount


```solidity
function getExecutionCount(
    bytes32 executionId
) external view returns (uint256);
```

### getAverageGasUsed


```solidity
function getAverageGasUsed(
    bytes32 executionId
) external view returns (uint256);
```

### getProtocolStats


```solidity
function getProtocolStats() external view returns (uint256 executions, uint256 gas);
```

## Events
### ExecutionRecorded

```solidity
event ExecutionRecorded(bytes32 indexed executionId, uint256 gasUsed, uint256 profit, bool success);
```

## Structs
### ExecutionRecord

```solidity
struct ExecutionRecord {
    uint256 timestamp;
    uint256 gasUsed;
    uint256 gasPrice;
    uint256 profit;
    bool success;
}
```

