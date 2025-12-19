# RiskEngine
[Git Source](https://github.com/example/superlib-arbitrage-protocol/blob/95c67768e2bfb00fae071b9d9bbef75272ead523/src/RiskEngine.sol)

**Inherits:**
Auth

**Title:**
RiskEngine

Calculates and validates risk scores for arbitrage operations

Uses Superlib Auth for role-based access control


## State Variables
### MAX_RISK_SCORE

```solidity
uint256 public constant MAX_RISK_SCORE = 100
```


### MIN_RISK_SCORE

```solidity
uint256 public constant MIN_RISK_SCORE = 0
```


### DEFAULT_RISK_SCORE

```solidity
uint256 public constant DEFAULT_RISK_SCORE = 50
```


### tokenRiskScores

```solidity
mapping(address => uint256) public tokenRiskScores
```


### pairRiskScores

```solidity
mapping(bytes32 => uint256) public pairRiskScores
```


### riskParams

```solidity
RiskParams public riskParams
```


### globalRiskMultiplier

```solidity
uint256 public globalRiskMultiplier = 100
```


## Functions
### constructor


```solidity
constructor(
    address _owner,
    Authority _authority
) Auth(_owner, _authority);
```

### evaluate


```solidity
function evaluate(
    address token,
    uint256 amount,
    uint256 /* deadline */
) external view returns (uint256 score);
```

### evaluatePair


```solidity
function evaluatePair(
    address tokenA,
    address tokenB,
    uint256 amountA,
    uint256 amountB
) external view returns (uint256 score);
```

### evaluateBatch


```solidity
function evaluateBatch(
    address[] calldata tokens,
    uint256[] calldata amounts
) external view returns (uint256[] memory scores);
```

### _calculateAmountAdjustment


```solidity
function _calculateAmountAdjustment(
    uint256 amount
) internal pure returns (uint256);
```

### _getPairId


```solidity
function _getPairId(
    address tokenA,
    address tokenB
) internal pure returns (bytes32);
```

### setTokenRiskScore


```solidity
function setTokenRiskScore(
    address token,
    uint256 score
) external requiresAuth;
```

### setPairRiskScore


```solidity
function setPairRiskScore(
    address tokenA,
    address tokenB,
    uint256 score
) external requiresAuth;
```

### setRiskParams


```solidity
function setRiskParams(
    uint256 volatilityWeight,
    uint256 liquidityWeight,
    uint256 correlationWeight,
    uint256 timeDecayFactor
) external requiresAuth;
```

### setGlobalRiskMultiplier


```solidity
function setGlobalRiskMultiplier(
    uint256 multiplier
) external requiresAuth;
```

### batchSetTokenRiskScores


```solidity
function batchSetTokenRiskScores(
    address[] calldata tokens,
    uint256[] calldata scores
) external requiresAuth;
```

## Events
### TokenRiskScoreUpdated

```solidity
event TokenRiskScoreUpdated(address indexed token, uint256 oldScore, uint256 newScore);
```

### PairRiskScoreUpdated

```solidity
event PairRiskScoreUpdated(bytes32 indexed pairId, uint256 oldScore, uint256 newScore);
```

### RiskParamsUpdated

```solidity
event RiskParamsUpdated(
    uint256 volatilityWeight, uint256 liquidityWeight, uint256 correlationWeight, uint256 timeDecay
);
```

### GlobalRiskMultiplierUpdated

```solidity
event GlobalRiskMultiplierUpdated(uint256 oldMultiplier, uint256 newMultiplier);
```

### RiskEvaluated

```solidity
event RiskEvaluated(address indexed token, uint256 amount, uint256 score);
```

## Errors
### InvalidRiskScore

```solidity
error InvalidRiskScore(uint256 score);
```

### ZeroAddress

```solidity
error ZeroAddress();
```

### InvalidWeight

```solidity
error InvalidWeight();
```

## Structs
### RiskParams

```solidity
struct RiskParams {
    uint256 volatilityWeight;
    uint256 liquidityWeight;
    uint256 correlationWeight;
    uint256 timeDecayFactor;
}
```

