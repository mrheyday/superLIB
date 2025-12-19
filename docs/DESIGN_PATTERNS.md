# Design Patterns Guide

Common Solidity patterns used in the Superlib Arbitrage Protocol.

## 1. Withdrawal Pattern (Pull Over Push)

### Problem
Direct transfers (`transfer()`, `send()`) can fail if recipient is a contract with a failing `receive()` function, making the calling contract stuck.

### Solution
Store pending amounts and let users withdraw themselves.

### Protocol Implementation

```solidity
// src/FeeVault.sol
contract FeeVault is ERC4626 {
    mapping(address => uint256) public pendingRewards;
    
    /// @notice Record rewards for a user (internal - called by protocol)
    function addRewards(address user, uint256 amount) external requiresAuth {
        pendingRewards[user] += amount;
        emit RewardsAdded(user, amount);
    }
    
    /// @notice Claim pending rewards (pull pattern - user initiates)
    function claimRewards() external returns (uint256 amount) {
        amount = pendingRewards[msg.sender];
        if (amount == 0) revert NoPendingRewards();
        
        // Zero before transfer (CEI pattern)
        pendingRewards[msg.sender] = 0;
        
        // Transfer to caller
        asset.safeTransfer(msg.sender, amount);
        emit RewardsClaimed(msg.sender, amount);
    }
}
```

**Why this matters:**
- Arbitrage profits are recorded asynchronously
- Users claim when gas is cheap
- Failed claims don't block protocol operations
- Attacker can't grief by making claims fail

## 2. Checks-Effects-Interactions (CEI)

### Problem
Reentrancy attacks occur when external calls are made before state is updated.

### Solution
Order operations: (1) Check conditions, (2) Update state, (3) External calls.

### Protocol Implementation

```solidity
// ❌ VULNERABLE - external call before state update
function withdraw(uint256 shares) external {
    uint256 assets = previewRedeem(shares);
    asset.safeTransfer(msg.sender, assets);  // External call FIRST
    _burn(msg.sender, shares);               // State update AFTER
}

// ✅ SAFE - CEI pattern
function withdraw(uint256 shares) external returns (uint256 assets) {
    // CHECKS
    if (shares == 0) revert ZeroShares();
    if (balanceOf[msg.sender] < shares) revert InsufficientBalance();
    
    // EFFECTS
    assets = previewRedeem(shares);
    _burn(msg.sender, shares);               // State update FIRST
    
    // INTERACTIONS
    asset.safeTransfer(msg.sender, assets);  // External call LAST
    
    emit Withdraw(msg.sender, assets, shares);
}
```

### With Reentrancy Guard

```solidity
// src/engines/FlashLoanEngine.sol
contract FlashLoanEngine {
    uint256 private locked = 1;
    
    modifier nonReentrant() {
        if (locked == 2) revert Reentrancy();
        locked = 2;
        _;
        locked = 1;
    }
    
    function executeFlashLoan(bytes calldata data) external nonReentrant {
        // Even with nonReentrant, still use CEI
        uint256 balanceBefore = asset.balanceOf(address(this));
        
        // Effects
        flashLoanActive = true;
        
        // Interactions
        IFlashLoanReceiver(msg.sender).onFlashLoan(data);
        
        // Post-checks
        if (asset.balanceOf(address(this)) < balanceBefore) {
            revert FlashLoanNotRepaid();
        }
        flashLoanActive = false;
    }
}
```

## 3. Role-Based Access Control (RBAC)

### Problem
Different users need different permissions. Single `onlyOwner` is too restrictive.

### Solution
Bitmap-based roles with capability mapping.

### Protocol Implementation

```solidity
// lib/superlib/auth/RolesAuthority.sol
contract RolesAuthority {
    // User -> Role bitmap (256 possible roles)
    mapping(address => bytes32) public getUserRoles;
    
    // Target -> Selector -> Required role bitmap
    mapping(address => mapping(bytes4 => bytes32)) public getRolesWithCapability;
    
    function canCall(
        address user,
        address target,
        bytes4 sig
    ) public view returns (bool) {
        // Check if user has ANY of the required roles
        return (getUserRoles[user] & getRolesWithCapability[target][sig]) != bytes32(0)
            || isCapabilityPublic[target][sig];
    }
    
    function setUserRole(address user, uint8 role, bool enabled) external requiresAuth {
        if (enabled) {
            getUserRoles[user] |= bytes32(1 << role);
        } else {
            getUserRoles[user] &= ~bytes32(1 << role);
        }
        emit UserRoleUpdated(user, role, enabled);
    }
}
```

```solidity
// src/roles/Roles.sol - Role definitions
library Roles {
    uint8 internal constant ADMIN = 0;
    uint8 internal constant EXECUTOR = 1;
    uint8 internal constant ARBITRAGE_MANAGER = 2;
    uint8 internal constant RISK_MANAGER = 3;
    uint8 internal constant CROSSCHAIN_OPERATOR = 4;
    uint8 internal constant STRATEGY_MANAGER = 5;
    uint8 internal constant UPDATER = 6;
    uint8 internal constant VAULT_DEPOSITOR = 7;  // P0 fix: separate from withdraw
    uint8 internal constant GUARDIAN = 8;          // P1 fix: emergency role
    uint8 internal constant FEE_UPDATER = 9;       // P1 fix: separated updater
    uint8 internal constant WHITELIST_ADMIN = 10;  // P1 fix: separated updater
}
```

**Protocol-specific patterns:**
- VAULT_DEPOSITOR can deposit but NOT withdraw (P0 security fix)
- GUARDIAN can pause but NOT unpause (emergency only)
- Roles are granted via multisig, not EOA

## 4. State Machine Pattern

### Problem
Contracts have different states where different actions are valid.

### Solution
Explicit state enum with modifiers.

### Protocol Implementation

```solidity
// src/engines/CrossChainRouter.sol
contract CrossChainRouter {
    enum MessageState {
        NonExistent,
        Queued,
        Executed,
        Cancelled,
        Failed
    }
    
    struct CrossChainMessage {
        MessageState state;
        uint64 queuedAt;
        bytes32 messageHash;
        bytes data;
    }
    
    mapping(bytes32 => CrossChainMessage) public messages;
    
    uint256 public constant TIMELOCK_DURATION = 24 hours;
    
    error InvalidState(MessageState current, MessageState required);
    
    modifier inState(bytes32 messageId, MessageState required) {
        MessageState current = messages[messageId].state;
        if (current != required) {
            revert InvalidState(current, required);
        }
        _;
    }
    
    modifier afterTimelock(bytes32 messageId) {
        if (block.timestamp < messages[messageId].queuedAt + TIMELOCK_DURATION) {
            revert TimelockNotExpired();
        }
        _;
    }
    
    /// @notice Queue a cross-chain message
    function queueMessage(bytes calldata data) 
        external 
        requiresAuth 
        returns (bytes32 messageId) 
    {
        messageId = keccak256(abi.encode(data, block.timestamp));
        
        messages[messageId] = CrossChainMessage({
            state: MessageState.Queued,
            queuedAt: uint64(block.timestamp),
            messageHash: keccak256(data),
            data: data
        });
        
        emit MessageQueued(messageId);
    }
    
    /// @notice Execute after timelock
    function executeMessage(bytes32 messageId)
        external
        requiresAuth
        inState(messageId, MessageState.Queued)
        afterTimelock(messageId)
    {
        messages[messageId].state = MessageState.Executed;
        
        // Execute the message
        _execute(messages[messageId].data);
        
        emit MessageExecuted(messageId);
    }
    
    /// @notice Cancel queued message
    function cancelMessage(bytes32 messageId)
        external
        requiresAuth
        inState(messageId, MessageState.Queued)
    {
        messages[messageId].state = MessageState.Cancelled;
        emit MessageCancelled(messageId);
    }
}
```

**State transitions:**
```
NonExistent -> Queued (via queueMessage)
Queued -> Executed (via executeMessage, after timelock)
Queued -> Cancelled (via cancelMessage)
Queued -> Failed (via internal failure)
```

## 5. Emergency Stop (Circuit Breaker)

### Problem
Exploits happen. Need ability to pause operations.

### Solution
Guardian role with pause capability.

### Protocol Implementation

```solidity
// src/StrategyOrchestrator.sol
contract StrategyOrchestrator {
    bool public paused;
    
    error ContractPaused();
    error ContractNotPaused();
    
    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }
    
    modifier whenPaused() {
        if (!paused) revert ContractNotPaused();
        _;
    }
    
    /// @notice Emergency pause - GUARDIAN role
    /// @custom:security Guardian can pause but CANNOT unpause
    function pause() external requiresAuth {
        paused = true;
        emit Paused(msg.sender);
    }
    
    /// @notice Resume operations - ADMIN role only
    function unpause() external requiresAuth {
        paused = false;
        emit Unpaused(msg.sender);
    }
    
    /// @notice Execute strategy - blocked when paused
    function executeStrategy(bytes calldata data) 
        external 
        requiresAuth 
        whenNotPaused 
    {
        _executeStrategy(data);
    }
}
```

**Guardian vs Admin:**
| Action | Guardian | Admin |
|--------|----------|-------|
| pause() | ✅ | ✅ |
| unpause() | ❌ | ✅ |
| revokeRole() | ❌ | ✅ |

## 6. Timelock Pattern

### Problem
Admin actions need delay for users to react/exit.

### Solution
Queue actions, enforce waiting period.

### Protocol Implementation

```solidity
// src/governance/QuantumArbitrage.sol
contract QuantumArbitrage {
    struct QueuedUpdate {
        bytes32 updateHash;
        uint64 queuedAt;
        bool executed;
    }
    
    uint256 public constant MIN_DELAY = 2 days;
    uint256 public constant MAX_DELAY = 30 days;
    
    mapping(bytes32 => QueuedUpdate) public queuedUpdates;
    
    function queueUpdate(
        address target,
        bytes calldata data,
        uint256 delay
    ) external requiresAuth returns (bytes32 updateId) {
        if (delay < MIN_DELAY || delay > MAX_DELAY) {
            revert InvalidDelay(delay);
        }
        
        updateId = keccak256(abi.encode(target, data, delay));
        
        queuedUpdates[updateId] = QueuedUpdate({
            updateHash: keccak256(data),
            queuedAt: uint64(block.timestamp),
            executed: false
        });
        
        emit UpdateQueued(updateId, target, delay);
    }
    
    function executeUpdate(
        bytes32 updateId,
        address target,
        bytes calldata data
    ) external requiresAuth {
        QueuedUpdate storage update = queuedUpdates[updateId];
        
        if (update.queuedAt == 0) revert UpdateNotQueued();
        if (update.executed) revert UpdateAlreadyExecuted();
        if (keccak256(data) != update.updateHash) revert DataMismatch();
        
        uint256 delay = block.timestamp - update.queuedAt;
        if (delay < MIN_DELAY) revert DelayNotPassed();
        if (delay > MAX_DELAY) revert UpdateExpired();
        
        update.executed = true;
        
        (bool success,) = target.call(data);
        if (!success) revert ExecutionFailed();
        
        emit UpdateExecuted(updateId, target);
    }
}
```

## 7. Factory Pattern

### Problem
Need to deploy multiple similar contracts.

### Solution
Factory contract with CREATE2 for deterministic addresses.

```solidity
// Example pattern (not in current protocol)
contract StrategyFactory {
    event StrategyDeployed(address indexed strategy, bytes32 salt);
    
    function deployStrategy(
        bytes32 salt,
        bytes calldata initData
    ) external returns (address strategy) {
        bytes memory bytecode = abi.encodePacked(
            type(Strategy).creationCode,
            initData
        );
        
        assembly {
            strategy := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        
        if (strategy == address(0)) revert DeploymentFailed();
        
        emit StrategyDeployed(strategy, salt);
    }
    
    function computeAddress(bytes32 salt, bytes calldata initData) 
        external 
        view 
        returns (address) 
    {
        bytes32 hash = keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            keccak256(abi.encodePacked(type(Strategy).creationCode, initData))
        ));
        return address(uint160(uint256(hash)));
    }
}
```

## 8. Proxy Patterns

### When to Use

| Pattern | Use Case | Protocol Usage |
|---------|----------|----------------|
| No Proxy | Immutable logic, simpler security | ✅ Current |
| UUPS | Upgradeable, minimal overhead | Consider for V2 |
| Beacon | Many instances, single upgrade | Strategy factories |
| Diamond | Complex modular systems | Avoid (complexity) |

**Current Protocol:** Non-upgradeable for security simplicity. Upgrades via new deployments with migration.

## Pattern Summary

| Pattern | Purpose | Protocol Files |
|---------|---------|----------------|
| Withdrawal | Pull payments | FeeVault |
| CEI | Reentrancy safety | All contracts |
| RBAC | Fine-grained access | RolesAuthority |
| State Machine | Valid transitions | CrossChainRouter |
| Circuit Breaker | Emergency stop | StrategyOrchestrator |
| Timelock | Delayed execution | QuantumArbitrage |

## Anti-Patterns to Avoid

### ❌ tx.origin for Auth
```solidity
// NEVER do this
if (tx.origin == owner) { ... }
```

### ❌ Unchecked External Calls
```solidity
// NEVER ignore return value
token.transfer(to, amount);  // ❌

// Always check or use SafeTransferLib
token.safeTransfer(to, amount);  // ✅
```

### ❌ Block.timestamp for Randomness
```solidity
// NEVER use for randomness
uint random = uint(keccak256(abi.encodePacked(block.timestamp)));  // ❌
```

### ❌ Delegatecall to Untrusted Contracts
```solidity
// NEVER delegatecall to user-provided address
address(target).delegatecall(data);  // ❌ if target is user-controlled
```
