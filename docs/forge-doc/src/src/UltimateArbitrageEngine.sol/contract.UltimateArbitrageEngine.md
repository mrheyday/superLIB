# UltimateArbitrageEngine
[Git Source](https://github.com/example/superlib-arbitrage-protocol/blob/95c67768e2bfb00fae071b9d9bbef75272ead523/src/UltimateArbitrageEngine.sol)

**Inherits:**
Auth, ReentrancyGuard

**Title:**
UltimateArbitrageEngine

Executes zero-capital arbitrage with flash loan pool whitelisting

Uses Superlib Auth for role-based access control


## State Variables
### whitelistedFlashLoanPools

```solidity
mapping(address => bool) public whitelistedFlashLoanPools
```


### authorizedExecutors

```solidity
mapping(address => bool) public authorizedExecutors
```


### feeVault

```solidity
address public feeVault
```


### performanceFeeBps

```solidity
uint256 public performanceFeeBps = 1000
```


## Functions
### constructor


```solidity
constructor(
    address _owner,
    Authority _authority,
    address _feeVault
) Auth(_owner, _authority);
```

### setFlashLoanPoolWhitelist


```solidity
function setFlashLoanPoolWhitelist(
    address pool,
    bool status
) external requiresAuth;
```

### setExecutorAuthorization


```solidity
function setExecutorAuthorization(
    address executor,
    bool status
) external requiresAuth;
```

### setFeeVault


```solidity
function setFeeVault(
    address _feeVault
) external requiresAuth;
```

### setPerformanceFee


```solidity
function setPerformanceFee(
    uint256 feeBps
) external requiresAuth;
```

### executeArbitrage


```solidity
function executeArbitrage(
    address flashLoanPool,
    address token,
    uint256 amount,
    bytes calldata arbitrageData
) external nonReentrant requiresAuth returns (uint256 profit);
```

### onFlashLoan


```solidity
function onFlashLoan(
    address initiator,
    address token,
    uint256 amount,
    uint256 fee,
    bytes calldata data
) external returns (bytes32);
```

### isPoolWhitelisted


```solidity
function isPoolWhitelisted(
    address pool
) external view returns (bool);
```

### isExecutorAuthorized


```solidity
function isExecutorAuthorized(
    address executor
) external view returns (bool);
```

## Events
### FlashLoanPoolWhitelisted

```solidity
event FlashLoanPoolWhitelisted(address indexed pool, bool status);
```

### ExecutorAuthorized

```solidity
event ExecutorAuthorized(address indexed executor, bool status);
```

### ArbitrageExecuted

```solidity
event ArbitrageExecuted(address indexed executor, address indexed token, uint256 profit, uint256 fee);
```

### FeeVaultUpdated

```solidity
event FeeVaultUpdated(address indexed oldVault, address indexed newVault);
```

### PerformanceFeeUpdated

```solidity
event PerformanceFeeUpdated(uint256 oldFee, uint256 newFee);
```

## Errors
### PoolNotWhitelisted

```solidity
error PoolNotWhitelisted(address pool);
```

### ZeroAddress

```solidity
error ZeroAddress();
```

### ZeroProfit

```solidity
error ZeroProfit();
```

### ExecutionFailed

```solidity
error ExecutionFailed();
```

### InvalidFee

```solidity
error InvalidFee(uint256 fee);
```

