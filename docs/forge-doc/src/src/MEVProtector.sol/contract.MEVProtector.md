# MEVProtector
[Git Source](https://github.com/example/superlib-arbitrage-protocol/blob/95c67768e2bfb00fae071b9d9bbef75272ead523/src/MEVProtector.sol)

**Inherits:**
Auth, ReentrancyGuard

**Title:**
MEVProtector

Commit-reveal scheme with target/selector whitelisting for MEV protection

Uses Superlib Auth for role-based access control


## State Variables
### COMMIT_DELAY

```solidity
uint256 public constant COMMIT_DELAY = 2
```


### COMMIT_EXPIRY

```solidity
uint256 public constant COMMIT_EXPIRY = 50
```


### COOLDOWN_PERIOD

```solidity
uint256 public constant COOLDOWN_PERIOD = 60
```


### commitments

```solidity
mapping(address => Commitment) public commitments
```


### lastExecutionTime

```solidity
mapping(address => uint256) public lastExecutionTime
```


### whitelistedTargets

```solidity
mapping(address => bool) public whitelistedTargets
```


### whitelistedSelectors

```solidity
mapping(address => mapping(bytes4 => bool)) public whitelistedSelectors
```


## Functions
### constructor


```solidity
constructor(
    address _owner,
    Authority _authority
) Auth(_owner, _authority);
```

### commitExecution


```solidity
function commitExecution(
    bytes32 commitHash
) external;
```

### executeProtectedArbitrage


```solidity
function executeProtectedArbitrage(
    address target,
    bytes calldata data,
    bytes32 salt
) external nonReentrant requiresAuth returns (bool success, bytes memory result);
```

### setTargetWhitelist


```solidity
function setTargetWhitelist(
    address target,
    bool status
) external requiresAuth;
```

### setSelectorWhitelist


```solidity
function setSelectorWhitelist(
    address target,
    bytes4 selector,
    bool status
) external requiresAuth;
```

### batchSetTargetWhitelist


```solidity
function batchSetTargetWhitelist(
    address[] calldata targets,
    bool[] calldata statuses
) external requiresAuth;
```

### batchSetSelectorWhitelist


```solidity
function batchSetSelectorWhitelist(
    address[] calldata targets,
    bytes4[] calldata selectors,
    bool[] calldata statuses
) external requiresAuth;
```

### getCommitment


```solidity
function getCommitment(
    address user
) external view returns (bytes32 hash, uint256 blockNumber);
```

### canExecute


```solidity
function canExecute(
    address user
) external view returns (bool);
```

## Events
### CommitmentMade

```solidity
event CommitmentMade(address indexed user, bytes32 hash, uint256 blockNumber);
```

### ProtectedExecutionComplete

```solidity
event ProtectedExecutionComplete(address indexed user, address indexed target, bool success);
```

### TargetWhitelistUpdated

```solidity
event TargetWhitelistUpdated(address indexed target, bool status);
```

### SelectorWhitelistUpdated

```solidity
event SelectorWhitelistUpdated(address indexed target, bytes4 selector, bool status);
```

### ThreatDetected

```solidity
event ThreatDetected(address indexed source, string threatType);
```

## Errors
### TargetNotWhitelisted

```solidity
error TargetNotWhitelisted(address target);
```

### SelectorNotWhitelisted

```solidity
error SelectorNotWhitelisted(address target, bytes4 selector);
```

### NoCommitmentFound

```solidity
error NoCommitmentFound();
```

### CommitmentTooRecent

```solidity
error CommitmentTooRecent(uint256 currentBlock, uint256 commitBlock, uint256 required);
```

### CommitmentExpired

```solidity
error CommitmentExpired(uint256 currentBlock, uint256 commitBlock, uint256 expiry);
```

### CommitmentMismatch

```solidity
error CommitmentMismatch(bytes32 expected, bytes32 provided);
```

### CooldownActive

```solidity
error CooldownActive(uint256 timeRemaining);
```

### ZeroAddress

```solidity
error ZeroAddress();
```

### ExecutionFailed

```solidity
error ExecutionFailed();
```

## Structs
### Commitment

```solidity
struct Commitment {
    bytes32 hash;
    uint256 blockNumber;
}
```

