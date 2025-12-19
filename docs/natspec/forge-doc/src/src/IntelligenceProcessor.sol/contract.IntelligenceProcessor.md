# IntelligenceProcessor
[Git Source](https://github.com/example/superlib-arbitrage-protocol/blob/95c67768e2bfb00fae071b9d9bbef75272ead523/src/IntelligenceProcessor.sol)

**Inherits:**
Auth

**Title:**
IntelligenceProcessor

Processes and stores arbitrage opportunity intelligence

Uses Superlib Auth for role-based access control


## State Variables
### MAX_OPPORTUNITIES_PER_TYPE

```solidity
uint256 public constant MAX_OPPORTUNITIES_PER_TYPE = 1000
```


### opportunities

```solidity
mapping(bytes32 => Opportunity) public opportunities
```


### opportunitiesByType

```solidity
mapping(OpportunityType => bytes32[]) public opportunitiesByType
```


### opportunityCount

```solidity
mapping(OpportunityType => uint256) public opportunityCount
```


## Functions
### constructor


```solidity
constructor(
    address _owner,
    Authority _authority
) Auth(_owner, _authority);
```

### addOpportunity


```solidity
function addOpportunity(
    bytes32 opportunityId,
    OpportunityType oppType,
    uint256 estimatedProfit,
    uint256 riskScore,
    uint256 expiryTime
) external requiresAuth;
```

### markProcessed


```solidity
function markProcessed(
    bytes32 opportunityId,
    bool success
) external requiresAuth;
```

### clearExpiredOpportunities


```solidity
function clearExpiredOpportunities(
    OpportunityType oppType
) external requiresAuth;
```

### getOpportunity


```solidity
function getOpportunity(
    bytes32 opportunityId
) external view returns (Opportunity memory);
```

### getOpportunitiesByType


```solidity
function getOpportunitiesByType(
    OpportunityType oppType
) external view returns (bytes32[] memory);
```

### getActiveOpportunities


```solidity
function getActiveOpportunities(
    OpportunityType oppType
) external view returns (bytes32[] memory);
```

## Events
### OpportunityAdded

```solidity
event OpportunityAdded(bytes32 indexed opportunityId, OpportunityType oppType, uint256 estimatedProfit);
```

### OpportunityProcessed

```solidity
event OpportunityProcessed(bytes32 indexed opportunityId, bool success);
```

### OpportunitiesCleared

```solidity
event OpportunitiesCleared(OpportunityType oppType, uint256 count);
```

## Errors
### MaxOpportunitiesReached

```solidity
error MaxOpportunitiesReached(OpportunityType oppType);
```

### OpportunityNotFound

```solidity
error OpportunityNotFound(bytes32 opportunityId);
```

### OpportunityExpired

```solidity
error OpportunityExpired(bytes32 opportunityId);
```

### OpportunityAlreadyProcessed

```solidity
error OpportunityAlreadyProcessed(bytes32 opportunityId);
```

## Structs
### Opportunity

```solidity
struct Opportunity {
    bytes32 opportunityId;
    OpportunityType oppType;
    uint256 estimatedProfit;
    uint256 riskScore;
    uint256 expiryTime;
    bool processed;
}
```

## Enums
### OpportunityType

```solidity
enum OpportunityType {
    PriceDiscrepancy,
    LiquidityImbalance,
    YieldDifferential,
    CrossChainArb,
    MEVExtraction
}
```

