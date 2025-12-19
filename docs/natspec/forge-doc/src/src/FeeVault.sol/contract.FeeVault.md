# FeeVault
[Git Source](https://github.com/example/superlib-arbitrage-protocol/blob/95c67768e2bfb00fae071b9d9bbef75272ead523/src/FeeVault.sol)

**Inherits:**
ERC4626, Auth, ReentrancyGuard

**Title:**
FeeVault

ERC4626 tokenized vault with fee collection and rewards distribution

Uses Superlib Auth for role-based access, inflation attack protection via dead shares


## State Variables
### MAX_FEE

```solidity
uint256 public constant MAX_FEE = 1000
```


### FEE_DENOMINATOR

```solidity
uint256 public constant FEE_DENOMINATOR = 10_000
```


### MINIMUM_SHARES

```solidity
uint256 public constant MINIMUM_SHARES = 1000
```


### MINIMUM_DEPOSIT

```solidity
uint256 public constant MINIMUM_DEPOSIT = 1000
```


### DEAD_ADDRESS

```solidity
address public constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD
```


### depositFee

```solidity
uint256 public depositFee
```


### withdrawFee

```solidity
uint256 public withdrawFee
```


### performanceFee

```solidity
uint256 public performanceFee
```


### feeRecipient

```solidity
address public feeRecipient
```


### rewardRate

```solidity
uint256 public rewardRate
```


### rewardReserves

```solidity
uint256 public rewardReserves
```


### lastRewardTime

```solidity
uint256 public lastRewardTime
```


### rewardPerShareStored

```solidity
uint256 public rewardPerShareStored
```


### userRewardPerSharePaid

```solidity
mapping(address => uint256) public userRewardPerSharePaid
```


### rewards

```solidity
mapping(address => uint256) public rewards
```


### totalDeposited

```solidity
uint256 public totalDeposited
```


### totalWithdrawn

```solidity
uint256 public totalWithdrawn
```


### paused

```solidity
bool public paused
```


## Functions
### constructor


```solidity
constructor(
    ERC20 _asset,
    string memory _name,
    string memory _symbol,
    address _feeRecipient,
    address _owner,
    Authority _authority
) ERC4626(_asset, _name, _symbol) Auth(_owner, _authority);
```

### initializeDeadShares

Initialize vault with dead share assets (call after deployment)


```solidity
function initializeDeadShares() external;
```

### whenNotPaused


```solidity
modifier whenNotPaused() ;
```

### deposit


```solidity
function deposit(
    uint256 assets,
    address receiver
) public virtual override nonReentrant whenNotPaused returns (uint256 shares);
```

### withdraw


```solidity
function withdraw(
    uint256 assets,
    address receiver,
    address _owner
) public virtual override nonReentrant whenNotPaused requiresAuth returns (uint256 shares);
```

### redeem


```solidity
function redeem(
    uint256 shares,
    address receiver,
    address _owner
) public virtual override nonReentrant whenNotPaused requiresAuth returns (uint256 assets);
```

### claimRewards


```solidity
function claimRewards() external nonReentrant whenNotPaused returns (uint256 reward);
```

### addRewards


```solidity
function addRewards(
    uint256 amount
) external requiresAuth;
```

### earned


```solidity
function earned(
    address account
) public view returns (uint256);
```

### rewardPerShare


```solidity
function rewardPerShare() public view returns (uint256);
```

### _updateReward


```solidity
function _updateReward(
    address account
) internal;
```

### setDepositFee


```solidity
function setDepositFee(
    uint256 newFee
) external requiresAuth;
```

### setWithdrawFee


```solidity
function setWithdrawFee(
    uint256 newFee
) external requiresAuth;
```

### setPerformanceFee


```solidity
function setPerformanceFee(
    uint256 newFee
) external requiresAuth;
```

### setFeeRecipient


```solidity
function setFeeRecipient(
    address newRecipient
) external requiresAuth;
```

### setRewardRate


```solidity
function setRewardRate(
    uint256 newRate
) external requiresAuth;
```

### pause


```solidity
function pause() external requiresAuth;
```

### unpause


```solidity
function unpause() external requiresAuth;
```

### emergencyWithdraw


```solidity
function emergencyWithdraw(
    address to,
    uint256 amount
) external requiresAuth;
```

### totalAssets


```solidity
function totalAssets() public view virtual override returns (uint256);
```

## Events
### DepositFeeUpdated

```solidity
event DepositFeeUpdated(uint256 oldFee, uint256 newFee);
```

### WithdrawFeeUpdated

```solidity
event WithdrawFeeUpdated(uint256 oldFee, uint256 newFee);
```

### PerformanceFeeUpdated

```solidity
event PerformanceFeeUpdated(uint256 oldFee, uint256 newFee);
```

### FeeRecipientUpdated

```solidity
event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
```

### FeesCollected

```solidity
event FeesCollected(address indexed recipient, uint256 amount);
```

### RewardRateUpdated

```solidity
event RewardRateUpdated(uint256 oldRate, uint256 newRate);
```

### RewardsClaimed

```solidity
event RewardsClaimed(address indexed user, uint256 amount);
```

### RewardsAdded

```solidity
event RewardsAdded(uint256 amount);
```

### Paused

```solidity
event Paused(address account);
```

### Unpaused

```solidity
event Unpaused(address account);
```

### EmergencyWithdraw

```solidity
event EmergencyWithdraw(address indexed to, uint256 amount);
```

## Errors
### FeeExceedsMax

```solidity
error FeeExceedsMax(uint256 fee, uint256 maxFee);
```

### ZeroAddress

```solidity
error ZeroAddress();
```

### ZeroAmount

```solidity
error ZeroAmount();
```

### InsufficientRewards

```solidity
error InsufficientRewards();
```

### DepositTooSmall

```solidity
error DepositTooSmall(uint256 amount, uint256 minimum);
```

### InsufficientRewardReserves

```solidity
error InsufficientRewardReserves(uint256 requested, uint256 available);
```

### ContractPaused

```solidity
error ContractPaused();
```

