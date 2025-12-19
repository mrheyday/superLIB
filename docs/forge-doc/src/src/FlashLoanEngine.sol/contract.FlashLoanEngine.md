# FlashLoanEngine
[Git Source](https://github.com/example/superlib-arbitrage-protocol/blob/95c67768e2bfb00fae071b9d9bbef75272ead523/src/FlashLoanEngine.sol)

**Inherits:**
Auth, ReentrancyGuard

**Title:**
FlashLoanEngine

Manages flash loan providers and executes zero-capital arbitrage

Uses Superlib Auth for role-based access control


## State Variables
### MAX_FEE_BPS

```solidity
uint256 public constant MAX_FEE_BPS = 500
```


### BPS_DENOMINATOR

```solidity
uint256 public constant BPS_DENOMINATOR = 10_000
```


### providers

```solidity
mapping(bytes32 => FlashLoanProvider) public providers
```


### providerIds

```solidity
bytes32[] public providerIds
```


### whitelistedDexRouters

```solidity
mapping(address => bool) public whitelistedDexRouters
```


### authorizedExecutors

```solidity
mapping(address => bool) public authorizedExecutors
```


### defaultSlippageBps

```solidity
uint256 public defaultSlippageBps = 50
```


### maxSlippageBps

```solidity
uint256 public maxSlippageBps = 500
```


## Functions
### constructor


```solidity
constructor(
    address _owner,
    Authority _authority
) Auth(_owner, _authority);
```

### addProvider


```solidity
function addProvider(
    bytes32 providerId,
    address provider,
    uint256 feeBps
) external requiresAuth;
```

### removeProvider


```solidity
function removeProvider(
    bytes32 providerId
) external requiresAuth;
```

### updateProvider


```solidity
function updateProvider(
    bytes32 providerId,
    uint256 newFeeBps,
    bool active
) external requiresAuth;
```

### setDexRouterWhitelist


```solidity
function setDexRouterWhitelist(
    address router,
    bool status
) external requiresAuth;
```

### setExecutorStatus


```solidity
function setExecutorStatus(
    address executor,
    bool status
) external requiresAuth;
```

### setSlippageLimits


```solidity
function setSlippageLimits(
    uint256 _defaultBps,
    uint256 _maxBps
) external requiresAuth;
```

### executeFlashLoanArbitrage


```solidity
function executeFlashLoanArbitrage(
    bytes32 providerId,
    address token,
    uint256 amount,
    address[] calldata dexPath,
    bytes[] calldata swapData,
    uint256 minProfit
) external nonReentrant requiresAuth returns (uint256 profit);
```

### getProvider


```solidity
function getProvider(
    bytes32 providerId
) external view returns (FlashLoanProvider memory);
```

### getProviderCount


```solidity
function getProviderCount() external view returns (uint256);
```

### getAllProviderIds


```solidity
function getAllProviderIds() external view returns (bytes32[] memory);
```

### isProviderActive


```solidity
function isProviderActive(
    bytes32 providerId
) external view returns (bool);
```

## Events
### ProviderAdded

```solidity
event ProviderAdded(bytes32 indexed providerId, address provider, uint256 feeBps);
```

### ProviderRemoved

```solidity
event ProviderRemoved(bytes32 indexed providerId);
```

### ProviderUpdated

```solidity
event ProviderUpdated(bytes32 indexed providerId, uint256 newFeeBps, bool active);
```

### DexRouterWhitelistUpdated

```solidity
event DexRouterWhitelistUpdated(address indexed router, bool status);
```

### ExecutorUpdated

```solidity
event ExecutorUpdated(address indexed executor, bool status);
```

### SlippageLimitsUpdated

```solidity
event SlippageLimitsUpdated(uint256 defaultBps, uint256 maxBps);
```

### FlashLoanExecuted

```solidity
event FlashLoanExecuted(bytes32 indexed providerId, address indexed token, uint256 amount, uint256 fee);
```

## Errors
### ProviderNotActive

```solidity
error ProviderNotActive(bytes32 providerId);
```

### ProviderAlreadyExists

```solidity
error ProviderAlreadyExists(bytes32 providerId);
```

### ProviderNotFound

```solidity
error ProviderNotFound(bytes32 providerId);
```

### FeeExceedsMax

```solidity
error FeeExceedsMax(uint256 fee, uint256 maxFee);
```

### DexNotWhitelisted

```solidity
error DexNotWhitelisted(address dex);
```

### ZeroAddress

```solidity
error ZeroAddress();
```

### ZeroAmount

```solidity
error ZeroAmount();
```

### SlippageExceedsMax

```solidity
error SlippageExceedsMax(uint256 slippage, uint256 maxSlippage);
```

### InsufficientProfit

```solidity
error InsufficientProfit(uint256 profit, uint256 required);
```

## Structs
### FlashLoanProvider

```solidity
struct FlashLoanProvider {
    address provider;
    uint256 feeBps;
    bool active;
}
```

