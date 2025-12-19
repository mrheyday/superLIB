# MinimumCostExecutor
[Git Source](https://github.com/example/superlib-arbitrage-protocol/blob/95c67768e2bfb00fae071b9d9bbef75272ead523/src/MinimumCostExecutor.sol)

**Inherits:**
Auth, ReentrancyGuard

**Title:**
MinimumCostExecutor

Optimizes execution costs with gas price management

Uses Superlib Auth for role-based access control


## State Variables
### maxCostPercentage

```solidity
uint256 public maxCostPercentage = 500
```


### defaultPriorityFee

```solidity
uint256 public defaultPriorityFee = 1 gwei
```


### maxGasPrice

```solidity
uint256 public maxGasPrice = 500 gwei
```


### executorGasRefunds

```solidity
mapping(address => uint256) public executorGasRefunds
```


## Functions
### constructor


```solidity
constructor(
    address _owner,
    Authority _authority
) Auth(_owner, _authority);
```

### executeWithMinimumCost


```solidity
function executeWithMinimumCost(
    address target,
    bytes calldata data,
    uint256 expectedProfit
) external nonReentrant requiresAuth returns (bool success, bytes memory result);
```

### setMaxCostPercentage


```solidity
function setMaxCostPercentage(
    uint256 newPercentage
) external requiresAuth;
```

### setDefaultPriorityFee


```solidity
function setDefaultPriorityFee(
    uint256 newFee
) external requiresAuth;
```

### setMaxGasPrice


```solidity
function setMaxGasPrice(
    uint256 newMaxGasPrice
) external requiresAuth;
```

### addGasRefund


```solidity
function addGasRefund(
    address executor,
    uint256 amount
) external requiresAuth;
```

### claimGasRefund


```solidity
function claimGasRefund() external nonReentrant;
```

### estimateCost


```solidity
function estimateCost(
    uint256 gasEstimate
) external view returns (uint256);
```

### isGasPriceAcceptable


```solidity
function isGasPriceAcceptable() external view returns (bool);
```

### receive


```solidity
receive() external payable;
```

## Events
### ExecutionCompleted

```solidity
event ExecutionCompleted(address indexed executor, uint256 gasUsed, uint256 cost, uint256 profit);
```

### MaxCostPercentageUpdated

```solidity
event MaxCostPercentageUpdated(uint256 oldValue, uint256 newValue);
```

### DefaultPriorityFeeUpdated

```solidity
event DefaultPriorityFeeUpdated(uint256 oldValue, uint256 newValue);
```

### MaxGasPriceUpdated

```solidity
event MaxGasPriceUpdated(uint256 oldValue, uint256 newValue);
```

### GasRefundClaimed

```solidity
event GasRefundClaimed(address indexed executor, uint256 amount);
```

## Errors
### CostExceedsLimit

```solidity
error CostExceedsLimit(uint256 cost, uint256 maxCost);
```

### GasPriceTooHigh

```solidity
error GasPriceTooHigh(uint256 gasPrice, uint256 maxGasPrice);
```

### NoRefundAvailable

```solidity
error NoRefundAvailable();
```

### ExecutionFailed

```solidity
error ExecutionFailed();
```

### InvalidPercentage

```solidity
error InvalidPercentage();
```

