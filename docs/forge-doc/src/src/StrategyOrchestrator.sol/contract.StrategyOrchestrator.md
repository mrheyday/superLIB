# StrategyOrchestrator
[Git Source](https://github.com/example/superlib-arbitrage-protocol/blob/95c67768e2bfb00fae071b9d9bbef75272ead523/src/StrategyOrchestrator.sol)

**Inherits:**
Auth

**Title:**
StrategyOrchestrator

Manages arbitrage strategies with bounded arrays and pagination

Uses Superlib Auth for role-based access control


## State Variables
### MAX_STRATEGIES

```solidity
uint256 public constant MAX_STRATEGIES = 100
```


### strategies

```solidity
mapping(bytes32 => StrategyConfig) public strategies
```


### strategyIds

```solidity
bytes32[] public strategyIds
```


### strategyTypeCount

```solidity
mapping(StrategyType => uint256) public strategyTypeCount
```


## Functions
### constructor


```solidity
constructor(
    address _owner,
    Authority _authority
) Auth(_owner, _authority);
```

### addStrategy


```solidity
function addStrategy(
    bytes32 strategyId,
    StrategyType strategyType,
    uint256 capitalAllocation,
    uint256 riskTolerance,
    uint256 profitTarget,
    uint256 stopLoss
) external requiresAuth;
```

### removeStrategy


```solidity
function removeStrategy(
    bytes32 strategyId
) external requiresAuth;
```

### updateStrategy


```solidity
function updateStrategy(
    bytes32 strategyId,
    uint256 capitalAllocation,
    uint256 riskTolerance,
    uint256 profitTarget,
    uint256 stopLoss
) external requiresAuth;
```

### toggleStrategy


```solidity
function toggleStrategy(
    bytes32 strategyId,
    bool active
) external requiresAuth;
```

### executeStrategyFlow


```solidity
function executeStrategyFlow(
    bytes32 strategyId
) external requiresAuth returns (bool);
```

### getStrategy


```solidity
function getStrategy(
    bytes32 strategyId
) external view returns (StrategyConfig memory);
```

### getStrategyCount


```solidity
function getStrategyCount() external view returns (uint256);
```

### getStrategiesPaginated


```solidity
function getStrategiesPaginated(
    uint256 offset,
    uint256 limit
) external view returns (StrategyConfig[] memory result, uint256 total);
```

### getActiveStrategies


```solidity
function getActiveStrategies() external view returns (bytes32[] memory);
```

### getStrategiesByType


```solidity
function getStrategiesByType(
    StrategyType strategyType
) external view returns (bytes32[] memory);
```

## Events
### StrategyAdded

```solidity
event StrategyAdded(bytes32 indexed strategyId, StrategyType strategyType, uint256 capitalAllocation);
```

### StrategyRemoved

```solidity
event StrategyRemoved(bytes32 indexed strategyId);
```

### StrategyUpdated

```solidity
event StrategyUpdated(bytes32 indexed strategyId, uint256 capitalAllocation, uint256 riskTolerance);
```

### StrategyExecuted

```solidity
event StrategyExecuted(bytes32 indexed strategyId, uint256 profit, uint256 timestamp);
```

### StrategyToggled

```solidity
event StrategyToggled(bytes32 indexed strategyId, bool active);
```

## Errors
### MaxStrategiesReached

```solidity
error MaxStrategiesReached(uint256 current, uint256 max);
```

### StrategyNotFound

```solidity
error StrategyNotFound(bytes32 strategyId);
```

### StrategyAlreadyExists

```solidity
error StrategyAlreadyExists(bytes32 strategyId);
```

### InvalidCapitalAllocation

```solidity
error InvalidCapitalAllocation();
```

### InvalidRiskTolerance

```solidity
error InvalidRiskTolerance();
```

### StrategyNotActive

```solidity
error StrategyNotActive(bytes32 strategyId);
```

## Structs
### StrategyConfig

```solidity
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
```

## Enums
### StrategyType

```solidity
enum StrategyType {
    TriangularArbitrage,
    CrossChainArbitrage,
    StatisticalArbitrage,
    VolatilityArbitrage,
    LiquidityArbitrage,
    MEVArbitrage
}
```

