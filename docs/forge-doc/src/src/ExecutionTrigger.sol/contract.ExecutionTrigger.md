# ExecutionTrigger
[Git Source](https://github.com/example/superlib-arbitrage-protocol/blob/95c67768e2bfb00fae071b9d9bbef75272ead523/src/ExecutionTrigger.sol)

**Inherits:**
Auth

**Title:**
ExecutionTrigger

Manages conditional execution triggers with bounded arrays

Uses Superlib Auth for role-based access control


## State Variables
### MAX_TRIGGERS

```solidity
uint256 public constant MAX_TRIGGERS = 50
```


### triggers

```solidity
mapping(bytes32 => Trigger) public triggers
```


### triggerIds

```solidity
bytes32[] public triggerIds
```


## Functions
### constructor


```solidity
constructor(
    address _owner,
    Authority _authority
) Auth(_owner, _authority);
```

### addTrigger


```solidity
function addTrigger(
    bytes32 triggerId,
    TriggerType triggerType,
    uint256 threshold,
    uint256 cooldown
) external requiresAuth;
```

### removeTrigger


```solidity
function removeTrigger(
    bytes32 triggerId
) external requiresAuth;
```

### updateThreshold


```solidity
function updateThreshold(
    bytes32 triggerId,
    uint256 newThreshold
) external requiresAuth;
```

### updateCooldown


```solidity
function updateCooldown(
    bytes32 triggerId,
    uint256 newCooldown
) external requiresAuth;
```

### toggleTrigger


```solidity
function toggleTrigger(
    bytes32 triggerId,
    bool active
) external requiresAuth;
```

### checkAndExecuteTriggers


```solidity
function checkAndExecuteTriggers(
    uint256 currentValue
) external requiresAuth returns (bytes32[] memory firedTriggers);
```

### getTrigger


```solidity
function getTrigger(
    bytes32 triggerId
) external view returns (Trigger memory);
```

### getTriggerCount


```solidity
function getTriggerCount() external view returns (uint256);
```

### getActiveTriggers


```solidity
function getActiveTriggers() external view returns (bytes32[] memory);
```

### canTriggerFire


```solidity
function canTriggerFire(
    bytes32 triggerId,
    uint256 currentValue
) external view returns (bool);
```

## Events
### TriggerAdded

```solidity
event TriggerAdded(bytes32 indexed triggerId, TriggerType triggerType, uint256 threshold);
```

### TriggerRemoved

```solidity
event TriggerRemoved(bytes32 indexed triggerId);
```

### TriggerUpdated

```solidity
event TriggerUpdated(bytes32 indexed triggerId, uint256 newThreshold, uint256 newCooldown);
```

### TriggerToggled

```solidity
event TriggerToggled(bytes32 indexed triggerId, bool active);
```

### TriggerFired

```solidity
event TriggerFired(bytes32 indexed triggerId, uint256 timestamp);
```

## Errors
### MaxTriggersReached

```solidity
error MaxTriggersReached(uint256 current, uint256 max);
```

### TriggerNotFound

```solidity
error TriggerNotFound(bytes32 triggerId);
```

### TriggerAlreadyExists

```solidity
error TriggerAlreadyExists(bytes32 triggerId);
```

### TriggerOnCooldown

```solidity
error TriggerOnCooldown(bytes32 triggerId, uint256 remainingTime);
```

### TriggerNotActive

```solidity
error TriggerNotActive(bytes32 triggerId);
```

## Structs
### Trigger

```solidity
struct Trigger {
    bytes32 triggerId;
    TriggerType triggerType;
    uint256 threshold;
    uint256 cooldown;
    uint256 lastTriggered;
    bool active;
}
```

## Enums
### TriggerType

```solidity
enum TriggerType {
    PriceThreshold,
    TimeInterval,
    VolumeSpike,
    VolatilityBreakout,
    LiquidityEvent
}
```

