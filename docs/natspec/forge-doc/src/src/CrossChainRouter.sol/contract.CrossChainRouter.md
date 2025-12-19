# CrossChainRouter
[Git Source](https://github.com/example/superlib-arbitrage-protocol/blob/95c67768e2bfb00fae071b9d9bbef75272ead523/src/CrossChainRouter.sol)

**Inherits:**
Auth, ReentrancyGuard

**Title:**
CrossChainRouter

Manages cross-chain trade execution with timelock-protected configuration

Uses Superlib Auth for role-based access control


## State Variables
### CONFIG_TIMELOCK

```solidity
uint256 public constant CONFIG_TIMELOCK = 24 hours
```


### chainConfigs

```solidity
mapping(uint256 => ChainConfig) public chainConfigs
```


### pendingConfigs

```solidity
mapping(uint256 => PendingConfig) public pendingConfigs
```


### dailyVolume

```solidity
mapping(uint256 => uint256) public dailyVolume
```


### dailyVolumeLimit

```solidity
mapping(uint256 => uint256) public dailyVolumeLimit
```


### lastVolumeReset

```solidity
mapping(uint256 => uint256) public lastVolumeReset
```


### supportedChains

```solidity
uint256[] public supportedChains
```


## Functions
### constructor


```solidity
constructor(
    address _owner,
    Authority _authority
) Auth(_owner, _authority);
```

### queueChainConfig


```solidity
function queueChainConfig(
    uint256 chainId,
    address bridge,
    uint256 minAmount,
    uint256 maxAmount,
    bool active
) external requiresAuth;
```

### executeChainConfig


```solidity
function executeChainConfig(
    uint256 chainId
) external requiresAuth;
```

### cancelPendingConfig


```solidity
function cancelPendingConfig(
    uint256 chainId
) external requiresAuth;
```

### setDailyLimit


```solidity
function setDailyLimit(
    uint256 chainId,
    uint256 limit
) external requiresAuth;
```

### executeCrossChainTrade


```solidity
function executeCrossChainTrade(
    uint256 chainId,
    address token,
    uint256 amount,
    bytes calldata bridgeData
) external nonReentrant requiresAuth returns (bytes32 messageId);
```

### _resetDailyVolumeIfNeeded


```solidity
function _resetDailyVolumeIfNeeded(
    uint256 chainId
) internal;
```

### getChainConfig


```solidity
function getChainConfig(
    uint256 chainId
) external view returns (ChainConfig memory);
```

### getPendingConfig


```solidity
function getPendingConfig(
    uint256 chainId
) external view returns (PendingConfig memory);
```

### getSupportedChains


```solidity
function getSupportedChains() external view returns (uint256[] memory);
```

### getRemainingDailyVolume


```solidity
function getRemainingDailyVolume(
    uint256 chainId
) external view returns (uint256);
```

### isChainActive


```solidity
function isChainActive(
    uint256 chainId
) external view returns (bool);
```

## Events
### ChainConfigQueued

```solidity
event ChainConfigQueued(
    uint256 indexed chainId, address bridge, uint256 minAmount, uint256 maxAmount, uint256 executeAfter
);
```

### ChainConfigExecuted

```solidity
event ChainConfigExecuted(uint256 indexed chainId, address bridge, uint256 minAmount, uint256 maxAmount);
```

### ChainConfigCancelled

```solidity
event ChainConfigCancelled(uint256 indexed chainId);
```

### DailyLimitUpdated

```solidity
event DailyLimitUpdated(uint256 indexed chainId, uint256 newLimit);
```

### CrossChainTradeExecuted

```solidity
event CrossChainTradeExecuted(uint256 indexed chainId, address indexed token, uint256 amount, bytes32 messageId);
```

### DailyVolumeReset

```solidity
event DailyVolumeReset(uint256 indexed chainId, uint256 timestamp);
```

## Errors
### ChainNotActive

```solidity
error ChainNotActive(uint256 chainId);
```

### ConfigTimelockActive

```solidity
error ConfigTimelockActive(uint256 chainId, uint256 executeAfter, uint256 currentTime);
```

### NoPendingConfig

```solidity
error NoPendingConfig(uint256 chainId);
```

### AmountBelowMinimum

```solidity
error AmountBelowMinimum(uint256 amount, uint256 minimum);
```

### AmountAboveMaximum

```solidity
error AmountAboveMaximum(uint256 amount, uint256 maximum);
```

### DailyVolumeLimitExceeded

```solidity
error DailyVolumeLimitExceeded(uint256 requested, uint256 remaining);
```

### ZeroAddress

```solidity
error ZeroAddress();
```

### InvalidChainId

```solidity
error InvalidChainId();
```

### BridgeCallFailed

```solidity
error BridgeCallFailed();
```

## Structs
### ChainConfig

```solidity
struct ChainConfig {
    address bridge;
    uint256 minAmount;
    uint256 maxAmount;
    bool active;
}
```

### PendingConfig

```solidity
struct PendingConfig {
    ChainConfig config;
    uint256 executeAfter;
    bool exists;
}
```

