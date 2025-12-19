# RolesAuthorityVerified
[Git Source](https://github.com/example/superlib-arbitrage-protocol/blob/95c67768e2bfb00fae071b9d9bbef75272ead523/src/RolesAuthorityVerified.sol)

**Inherits:**
RolesAuthority

**Title:**
RolesAuthorityVerified

**Author:**
Superlib Arbitrage Protocol Team

RolesAuthority wrapper with SMTChecker formal verification targets

Extends RolesAuthority with assert statements for CHC/BMC verification.
Run verification with:
solc --model-checker-engine chc --model-checker-targets assert \
--model-checker-show-proved-safe src/RolesAuthorityVerified.sol

**Notes:**
- security: Formal verification via Solidity SMTChecker (CHC + BMC)

- smtchecker: abstract-function-nondet


## State Variables
### isBlacklisted
Addresses that should NEVER have any role (adversary modeling)

Used by SMTChecker to prove privilege escalation is impossible


```solidity
mapping(address => bool) public isBlacklisted
```


### originalOwner
Original deployer address for ownership invariant


```solidity
address public immutable originalOwner
```


### roleGrantCount
Count of successful role grants (for state property verification)


```solidity
uint256 public roleGrantCount
```


## Functions
### constructor

Deploy with owner who will manage roles

SMTChecker verifies: owner is set correctly at construction


```solidity
constructor(
    address _owner,
    Authority _authority
) RolesAuthority(_owner, _authority);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_owner`|`address`|Address that will own the authority|
|`_authority`|`Authority`|Optional parent authority (usually address(0))|


### blacklist

Mark address as adversary (cannot ever receive roles)

Used to model attackers for formal verification


```solidity
function blacklist(
    address account
) external requiresAuth;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|Address to blacklist|


### checkBlacklisted

Check if address is blacklisted


```solidity
function checkBlacklisted(
    address account
) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|Address to check|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|True if blacklisted|


### setUserRole

Set user role with formal verification assertions

CHC verifies across multiple transactions:
- Blacklisted users NEVER gain roles
- Role bitmask is updated correctly


```solidity
function setUserRole(
    address user,
    uint8 role,
    bool enabled
) public virtual override requiresAuth;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address to modify roles for|
|`role`|`uint8`|Role ID (0-255) to set|
|`enabled`|`bool`|True to grant, false to revoke|


### canCall

Check if user can call function (with verification)

SMT verifies: users with no roles can only call public functions


```solidity
function canCall(
    address user,
    address target,
    bytes4 functionSig
) public view virtual override returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|Address attempting the call|
|`target`|`address`|Contract being called|
|`functionSig`|`bytes4`|Function selector being called|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|Whether user is authorized|


### verifyP0_DepositorCannotWithdraw

Verify P0: VAULT_DEPOSITOR cannot have withdraw capability

Call after wiring capabilities to formally prove P0 fix


```solidity
function verifyP0_DepositorCannotWithdraw(
    address vaultAddress,
    bytes4 withdrawSelector
) external view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`vaultAddress`|`address`|FeeVault contract address|
|`withdrawSelector`|`bytes4`|bytes4(keccak256("withdraw(uint256,address,address)"))|


### verifyP0_DepositorCannotRedeem

Verify P0: VAULT_DEPOSITOR cannot have redeem capability


```solidity
function verifyP0_DepositorCannotRedeem(
    address vaultAddress,
    bytes4 redeemSelector
) external view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`vaultAddress`|`address`|FeeVault contract address|
|`redeemSelector`|`bytes4`|bytes4(keccak256("redeem(uint256,address,address)"))|


### verifyP0_PauseRestriction

Verify P0: Only ADMIN and GUARDIAN can pause


```solidity
function verifyP0_PauseRestriction(
    address vaultAddress,
    bytes4 pauseSelector
) external view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`vaultAddress`|`address`|FeeVault contract address|
|`pauseSelector`|`bytes4`|bytes4(keccak256("pause()"))|


### verifyP1_ExecutorNoWhitelist

Verify P1: EXECUTOR cannot modify whitelists


```solidity
function verifyP1_ExecutorNoWhitelist(
    address mevProtectorAddress,
    bytes4 setWhitelistSelector
) external view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`mevProtectorAddress`|`address`|MEVProtector contract|
|`setWhitelistSelector`|`bytes4`|bytes4(keccak256("setTargetWhitelist(address,bool)"))|


### verifyP1_FeeUpdaterNoPause

Verify P1: FEE_UPDATER cannot pause


```solidity
function verifyP1_FeeUpdaterNoPause(
    address vaultAddress,
    bytes4 pauseSelector
) external view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`vaultAddress`|`address`|FeeVault contract|
|`pauseSelector`|`bytes4`|bytes4(keccak256("pause()"))|


### verifyP1_ArbitrageManagerNoWithdraw

Verify P1: ARBITRAGE_MANAGER cannot withdraw from vault


```solidity
function verifyP1_ArbitrageManagerNoWithdraw(
    address vaultAddress,
    bytes4 withdrawSelector
) external view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`vaultAddress`|`address`|FeeVault contract|
|`withdrawSelector`|`bytes4`|bytes4(keccak256("withdraw(uint256,address,address)"))|


### verifyOwnershipInvariant

Verify ownership cannot become zero

BMC + CHC verify this holds across all transactions


```solidity
function verifyOwnershipInvariant() external view;
```

### verifyOwnershipTransfer

Simulate ownership transfer and verify invariants

For testing transfer scenarios with SMTChecker


```solidity
function verifyOwnershipTransfer(
    address newOwner
) external view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newOwner`|`address`|Proposed new owner|


### simulateExternalCall

External call simulation for reentrancy analysis

CHC engine will analyze if reentrancy can violate invariants


```solidity
function simulateExternalCall(
    address target
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`target`|`address`|External contract to call|


