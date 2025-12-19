# API Reference

This document provides detailed reference information for all public functions, events, and errors in the protocol contracts.

## FeeVault

The FeeVault is an ERC4626-compliant tokenized vault that collects protocol fees and distributes rewards to depositors. It includes protection against first-depositor inflation attacks through dead shares.

### Constants

```solidity
uint256 public constant MAX_FEE = 1000;           // 10% maximum fee
uint256 public constant FEE_DENOMINATOR = 10000;  // Basis points denominator
uint256 public constant MINIMUM_SHARES = 1000;    // Dead shares for inflation protection
uint256 public constant MINIMUM_DEPOSIT = 1000;   // Minimum deposit amount in wei
address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
```

### State Variables

```solidity
uint256 public depositFee;           // Fee charged on deposits (basis points)
uint256 public withdrawFee;          // Fee charged on withdrawals (basis points)
uint256 public performanceFee;       // Performance fee (basis points)
address public feeRecipient;         // Address receiving collected fees
uint256 public rewardRate;           // Rewards distributed per second
uint256 public rewardReserves;       // Available reward token reserves
uint256 public totalDeposited;       // Cumulative deposits
uint256 public totalWithdrawn;       // Cumulative withdrawals
```

### Functions

#### deposit

```solidity
function deposit(uint256 assets, address receiver) external returns (uint256 shares)
```

Deposits assets into the vault and mints shares to the receiver. The deposit fee is deducted from assets before calculating shares. Reverts if assets are below `MINIMUM_DEPOSIT` or if receiver is the zero address.

#### withdraw

```solidity
function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares)
```

Withdraws the specified asset amount from the vault. The caller must have approval from the owner if not the owner themselves. Withdrawal fees are deducted from the gross amount.

#### redeem

```solidity
function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets)
```

Burns shares and returns the corresponding assets to the receiver. Withdrawal fees reduce the received assets.

#### claimRewards

```solidity
function claimRewards() external returns (uint256 reward)
```

Claims accumulated staking rewards for the caller. Reverts with `InsufficientRewardReserves` if reserves cannot cover the earned amount.

#### addRewards

```solidity
function addRewards(uint256 amount) external
```

Adds reward tokens to the reserve pool. Requires `REWARDS_MANAGER_ROLE`. The caller must have approved the vault to transfer the reward tokens.

#### setDepositFee / setWithdrawFee / setPerformanceFee

```solidity
function setDepositFee(uint256 newFee) external
function setWithdrawFee(uint256 newFee) external
function setPerformanceFee(uint256 newFee) external
```

Updates fee parameters. Requires `FEE_MANAGER_ROLE`. Reverts with `FeeExceedsMax` if the new fee exceeds `MAX_FEE`.

### Events

```solidity
event DepositFeeUpdated(uint256 oldFee, uint256 newFee);
event WithdrawFeeUpdated(uint256 oldFee, uint256 newFee);
event PerformanceFeeUpdated(uint256 oldFee, uint256 newFee);
event FeeRecipientUpdated(address oldRecipient, address newRecipient);
event FeesCollected(address indexed recipient, uint256 amount);
event RewardRateUpdated(uint256 oldRate, uint256 newRate);
event RewardsClaimed(address indexed user, uint256 amount);
event RewardsAdded(uint256 amount);
```

### Errors

```solidity
error FeeExceedsMax(uint256 fee, uint256 maxFee);
error ZeroAddress();
error ZeroAmount();
error InsufficientRewards();
error DepositTooSmall(uint256 amount, uint256 minimum);
error InsufficientRewardReserves(uint256 requested, uint256 available);
```

## MEVProtector

The MEVProtector implements a commit-reveal scheme to protect arbitrage executions from front-running attacks. Users must commit to their execution parameters and wait before executing.

### Constants

```solidity
uint256 public constant COMMIT_DELAY = 2;     // Minimum blocks between commit and execute
uint256 public constant COMMIT_EXPIRY = 50;   // Maximum blocks before commitment expires
uint256 public constant COOLDOWN_PERIOD = 60; // Seconds between executions per user
```

### State Variables

```solidity
mapping(address => bool) public whitelistedTargets;       // Approved target contracts
mapping(bytes4 => bool) public allowedFunctionSelectors;  // Approved function selectors
mapping(bytes32 => uint256) public commitments;           // Commitment hash => block number
mapping(address => uint256) public lastExecutionTime;     // User => last execution timestamp
mapping(address => bool) public authorizedExecutors;      // Approved callers
```

### Functions

#### commitExecution

```solidity
function commitExecution(bytes32 commitment) external
```

Stores a commitment hash for later execution. The commitment should be `keccak256(abi.encodePacked(target, data, salt, msg.sender))`. Users must wait `COMMIT_DELAY` blocks before executing.

#### executeProtectedArbitrage

```solidity
function executeProtectedArbitrage(
    address target,
    bytes calldata data,
    bytes32 salt
) external returns (bytes memory result)
```

Executes a protected call to the target contract. Validates that the target is whitelisted, the function selector is allowed, a valid commitment exists, the commitment timing is valid (after delay, before expiry), and the cooldown period has elapsed.

#### setWhitelistedTarget

```solidity
function setWhitelistedTarget(address target, bool whitelisted) external
```

Adds or removes a target from the whitelist. Owner only.

#### setAllowedFunctionSelector

```solidity
function setAllowedFunctionSelector(bytes4 selector, bool allowed) external
```

Adds or removes a function selector from the allowed list. Owner only.

### Events

```solidity
event ExecutionCommitted(address indexed executor, bytes32 commitment, uint256 blockNumber);
event ProtectedExecutionCompleted(address indexed executor, address target, uint256 blockNumber);
event TargetWhitelisted(address indexed target, bool whitelisted);
event FunctionSelectorAllowed(bytes4 indexed selector, bool allowed);
```

### Errors

```solidity
error TargetNotWhitelisted(address target);
error FunctionNotAllowed(bytes4 selector);
error NoCommitmentFound();
error CommitmentTooRecent(uint256 currentBlock, uint256 commitBlock);
error CommitmentExpired(uint256 currentBlock, uint256 commitBlock);
error CooldownActive(uint256 remainingTime);
error UnauthorizedExecutor();
```

## FlashLoanEngine

The FlashLoanEngine manages flash loan providers and executes arbitrage paths with validated DEX routers.

### Constants

```solidity
uint256 public constant MAX_FEE_BPS = 500; // 5% maximum provider fee
```

### State Variables

```solidity
mapping(bytes32 => FlashLoanProvider) public providers;  // Provider configurations
mapping(address => bool) public authorizedCallers;       // Approved callers
mapping(address => bool) public whitelistedDexRouters;   // Approved DEX routers
uint256 public totalFlashLoans;                          // Execution counter
uint256 public totalProfitGenerated;                     // Cumulative profit
```

### Structs

```solidity
struct FlashLoanProvider {
    address provider;  // Provider contract address
    uint256 fee;       // Fee in basis points
    bool active;       // Whether provider is active
}
```

### Functions

#### executeFlashLoanArbitrage

```solidity
function executeFlashLoanArbitrage(
    address[] memory path,
    uint256 amount,
    uint256 minProfit,
    address[] memory dexRouters
) external returns (uint256 profit)
```

Executes a flash loan arbitrage along the specified token path. Each DEX router in the array must be whitelisted. The path length must be at least 2, and `dexRouters` length must equal `path.length - 1`.

#### addProvider

```solidity
function addProvider(bytes32 providerId, address provider, uint256 fee) external
```

Registers a new flash loan provider. Owner only. The fee must not exceed `MAX_FEE_BPS`.

#### removeProvider

```solidity
function removeProvider(bytes32 providerId) external
```

Deactivates and removes a flash loan provider. Owner only.

#### setDexRouterWhitelist

```solidity
function setDexRouterWhitelist(address router, bool whitelisted) external
```

Adds or removes a DEX router from the whitelist. Owner only.

### Events

```solidity
event FlashLoanExecuted(address indexed provider, address indexed token, uint256 amount, uint256 profit);
event ProviderAdded(bytes32 indexed providerId, address provider, uint256 fee);
event ProviderRemoved(bytes32 indexed providerId);
event AuthorizedCallerUpdated(address indexed caller, bool authorized);
event DexRouterWhitelisted(address indexed router, bool whitelisted);
```

### Errors

```solidity
error UnauthorizedCaller();
error ProviderNotActive();
error InsufficientProfit();
error ZeroAddress();
error InvalidPath();
error FeeTooHigh(uint256 fee, uint256 maxFee);
error DexNotWhitelisted(address dex);
```

## CrossChainRouter

The CrossChainRouter manages cross-chain trade execution with timelock-protected configuration changes.

### Constants

```solidity
uint256 public constant CONFIG_TIMELOCK = 24 hours; // Configuration change delay
```

### State Variables

```solidity
mapping(uint256 => ChainConfig) public chainConfigs;     // Chain ID => configuration
mapping(uint256 => PendingConfig) public pendingConfigs; // Queued changes
mapping(address => bool) public authorizedExecutors;     // Approved callers
mapping(uint256 => uint256) public dailyVolume;          // Chain ID => today's volume
uint256 public maxDailyVolumePerChain;                   // Daily limit per chain
```

### Structs

```solidity
struct ChainConfig {
    address bridge;      // Bridge contract address
    uint256 minAmount;   // Minimum trade amount
    uint256 maxAmount;   // Maximum trade amount
    bool active;         // Whether chain is active
}

struct PendingConfig {
    address bridge;
    uint256 minAmount;
    uint256 maxAmount;
    bool active;
    uint256 effectiveTime; // When change can be executed
}
```

### Functions

#### queueChainConfig

```solidity
function queueChainConfig(
    uint256 chainId,
    address bridge,
    uint256 minAmount,
    uint256 maxAmount,
    bool active
) external
```

Queues a chain configuration change. Owner only. The change becomes executable after `CONFIG_TIMELOCK` seconds.

#### executeChainConfig

```solidity
function executeChainConfig(uint256 chainId) external
```

Executes a previously queued configuration change. Reverts with `ConfigTimelockActive` if the timelock has not expired.

#### executeChainTrade

```solidity
function executeChainTrade(
    uint256 destinationChainId,
    address token,
    uint256 amount,
    bytes calldata bridgeData
) external returns (bytes32 messageId)
```

Executes a cross-chain trade through the configured bridge. Validates the chain is active, amount is within bounds, and daily volume limit is not exceeded.

### Events

```solidity
event ChainConfigQueued(uint256 indexed chainId, address bridge, uint256 effectiveTime);
event ChainConfigUpdated(uint256 indexed chainId, address bridge, uint256 minAmount, uint256 maxAmount);
event CrossChainTradeExecuted(uint256 indexed chainId, address token, uint256 amount, bytes32 messageId);
```

### Errors

```solidity
error ConfigTimelockActive(uint256 effectiveTime);
error NoPendingConfig();
error ChainNotActive(uint256 chainId);
error AmountOutOfRange(uint256 amount, uint256 min, uint256 max);
error DailyVolumeLimitExceeded(uint256 requested, uint256 remaining);
error ZeroAddress();
```

## StrategyOrchestrator

The StrategyOrchestrator manages arbitrage strategies with bounded arrays and pagination.

### Constants

```solidity
uint256 public constant MAX_STRATEGIES = 100; // Maximum strategies allowed
```

### State Variables

```solidity
mapping(bytes32 => StrategyConfig) public activeStrategies;  // Strategy configurations
bytes32[] public strategyList;                                // Array of strategy hashes
uint256 public activeStrategyCount;                           // Count of active strategies
```

### Enums

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

### Structs

```solidity
struct StrategyConfig {
    StrategyType strategyType;
    uint256 capitalAllocation;
    uint256 riskTolerance;
    uint256 profitTarget;
    uint256 stopLoss;
    uint256 priorityScore;
    bool active;
    uint256 createdAt;
}
```

### Functions

#### addStrategy

```solidity
function addStrategy(
    StrategyType strategyType,
    uint256 capital,
    uint256 risk,
    uint256 profitTarget,
    uint256 stopLoss
) external returns (bytes32 strategyHash)
```

Creates a new strategy configuration. Owner only. Reverts with `MaxStrategiesReached` if the limit is exceeded.

#### removeStrategy

```solidity
function removeStrategy(bytes32 strategyHash) external
```

Deactivates a strategy. Owner only.

#### getStrategiesPaginated

```solidity
function getStrategiesPaginated(
    uint256 offset,
    uint256 limit
) external view returns (bytes32[] memory strategies, uint256 total)
```

Returns a page of strategy hashes. Use for iterating over large strategy lists without gas exhaustion.

### Events

```solidity
event StrategyAdded(bytes32 indexed strategyHash, StrategyType strategyType, uint256 timestamp);
event StrategyRemoved(bytes32 indexed strategyHash);
event StrategyToggled(bytes32 indexed strategyHash, bool active);
```

### Errors

```solidity
error StrategyNotFound(bytes32 strategyHash);
error StrategyNotActive(bytes32 strategyHash);
error MaxStrategiesReached(uint256 max);
error StrategyAlreadyExists(bytes32 strategyHash);
error InvalidParameters();
```

## MaximumSecurityEngine

The MaximumSecurityEngine provides rate-limited, validated external calls with comprehensive security checks.

### Constants

```solidity
uint256 public constant MAX_CALLS_PER_PERIOD = 10; // Maximum calls per rate limit period
uint256 public constant RATE_LIMIT_PERIOD = 60;    // Rate limit period in seconds
```

### State Variables

```solidity
mapping(address => bool) public whitelistedTargets;       // Approved target contracts
mapping(bytes4 => bool) public allowedFunctionSelectors;  // Approved function selectors
mapping(address => bool) public authorizedAddresses;      // Approved callers
mapping(address => bool) public blacklistedAddresses;     // Blocked addresses
mapping(address => uint256) public callCount;             // Rate limit tracking
mapping(address => uint256) public periodStart;           // Rate limit period start
uint256 public minSecurityScore;                          // Minimum score for execution
```

### Functions

#### executeWithMaximumSecurity

```solidity
function executeWithMaximumSecurity(
    address target,
    bytes4 selector,
    bytes memory params,
    address userAddress
) external returns (bool securityValidated)
```

Executes a validated call to the target contract. Validates target whitelist, selector whitelist, rate limits, access controls, threat detection, and security score requirements.

#### setWhitelistedTarget / setAllowedFunctionSelector

```solidity
function setWhitelistedTarget(address target, bool whitelisted) external
function setAllowedFunctionSelector(bytes4 selector, bool allowed) external
```

Manages whitelists. Owner only.

### Events

```solidity
event SecurityValidated(address indexed target, bytes4 selector, uint256 securityScore);
event ThreatDetected(address indexed target, string reason);
event TargetWhitelisted(address indexed target, bool whitelisted);
event FunctionSelectorAllowed(bytes4 indexed selector, bool allowed);
```

### Errors

```solidity
error TargetNotWhitelisted(address target);
error FunctionNotAllowed(bytes4 selector);
error RateLimitExceeded(address user, uint256 count, uint256 max);
error AccessControlViolation();
error BlacklistedAddress();
error SecurityScoreTooLow(uint256 score, uint256 minimum);
```
