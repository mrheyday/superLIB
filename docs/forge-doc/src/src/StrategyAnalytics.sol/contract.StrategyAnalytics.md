# StrategyAnalytics
[Git Source](https://github.com/example/superlib-arbitrage-protocol/blob/95c67768e2bfb00fae071b9d9bbef75272ead523/src/StrategyAnalytics.sol)

**Inherits:**
Auth

**Title:**
StrategyAnalytics

Tracks execution metrics for arbitrage strategies

Uses Superlib Auth for role-based access control


## State Variables
### strategyMetrics

```solidity
mapping(bytes32 => StrategyMetrics) public strategyMetrics
```


### executorTradeCount

```solidity
mapping(address => uint256) public executorTradeCount
```


### totalProtocolProfit

```solidity
uint256 public totalProtocolProfit
```


### totalProtocolTrades

```solidity
uint256 public totalProtocolTrades
```


## Functions
### constructor


```solidity
constructor(
    address _owner,
    Authority _authority
) Auth(_owner, _authority);
```

### recordTrade


```solidity
function recordTrade(
    bytes32 strategyId,
    bool success,
    uint256 profit,
    uint256 loss,
    uint256 executionTime
) external requiresAuth;
```

### resetMetrics


```solidity
function resetMetrics(
    bytes32 strategyId
) external requiresAuth;
```

### getMetrics


```solidity
function getMetrics(
    bytes32 strategyId
) external view returns (StrategyMetrics memory);
```

### getSuccessRate


```solidity
function getSuccessRate(
    bytes32 strategyId
) external view returns (uint256);
```

### getNetProfit


```solidity
function getNetProfit(
    bytes32 strategyId
) external view returns (int256);
```

### getProtocolStats


```solidity
function getProtocolStats() external view returns (uint256 trades, uint256 profit);
```

## Events
### TradeRecorded

```solidity
event TradeRecorded(bytes32 indexed strategyId, bool success, uint256 profit, uint256 loss);
```

### MetricsReset

```solidity
event MetricsReset(bytes32 indexed strategyId);
```

## Errors
### ZeroStrategyId

```solidity
error ZeroStrategyId();
```

## Structs
### StrategyMetrics

```solidity
struct StrategyMetrics {
    uint256 totalTrades;
    uint256 successfulTrades;
    uint256 totalProfit;
    uint256 totalLoss;
    uint256 lastExecutionTime;
    uint256 avgExecutionTime;
}
```

