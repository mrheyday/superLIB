# YulHelpers
[Git Source](https://github.com/example/superlib-arbitrage-protocol/blob/95c67768e2bfb00fae071b9d9bbef75272ead523/src/utils/YulHelpers.sol)

**Title:**
YulHelpers

**Author:**
Superlib Arbitrage Protocol Team

Gas-optimized utility functions using Yul (inline assembly)

These functions bypass Solidity's safety checks - use only after validation

**Note:**
security: Manual audit required - SMTChecker cannot verify assembly


## Functions
### hasRole

Check if a role bit is set in the roles bitmask


```solidity
function hasRole(
    bytes32 roles,
    uint8 role
) internal pure returns (bool has);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`roles`|`bytes32`|The 256-bit roles bitmask|
|`role`|`uint8`|The role ID (0-255) to check|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`has`|`bool`|True if role bit is set|


### setRole

Set a role bit in the roles bitmask


```solidity
function setRole(
    bytes32 roles,
    uint8 role
) internal pure returns (bytes32 newRoles);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`roles`|`bytes32`|The current roles bitmask|
|`role`|`uint8`|The role ID to enable|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`newRoles`|`bytes32`|Updated bitmask with role enabled|


### clearRole

Clear a role bit in the roles bitmask


```solidity
function clearRole(
    bytes32 roles,
    uint8 role
) internal pure returns (bytes32 newRoles);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`roles`|`bytes32`|The current roles bitmask|
|`role`|`uint8`|The role ID to disable|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`newRoles`|`bytes32`|Updated bitmask with role disabled|


### hasAnyRole

Check if any role in a capability mask matches user roles


```solidity
function hasAnyRole(
    bytes32 userRoles,
    bytes32 capability
) internal pure returns (bool authorized);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`userRoles`|`bytes32`|User's role bitmask|
|`capability`|`bytes32`|Function's required role bitmask|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`authorized`|`bool`|True if user has at least one required role|


### calldataAddress

Extract address from calldata at offset


```solidity
function calldataAddress(
    uint256 offset
) internal pure returns (address addr);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`offset`|`uint256`|Byte offset in calldata|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`addr`|`address`|The address at that offset|


### calldataUint

Extract uint256 from calldata at offset


```solidity
function calldataUint(
    uint256 offset
) internal pure returns (uint256 val);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`offset`|`uint256`|Byte offset in calldata|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`val`|`uint256`|The uint256 value|


### mappingSlot

Compute storage slot for mapping(address => bytes32)


```solidity
function mappingSlot(
    address key,
    uint256 slot
) internal pure returns (bytes32 storageSlot);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`key`|`address`|The mapping key (address)|
|`slot`|`uint256`|The base storage slot of the mapping|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`storageSlot`|`bytes32`|The computed storage slot|


### uncheckedAdd

Unchecked addition (use when overflow impossible)


```solidity
function uncheckedAdd(
    uint256 a,
    uint256 b
) internal pure returns (uint256 c);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`a`|`uint256`|First operand|
|`b`|`uint256`|Second operand|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`c`|`uint256`|Sum without overflow check|


### uncheckedSub

Unchecked subtraction (use when underflow impossible)


```solidity
function uncheckedSub(
    uint256 a,
    uint256 b
) internal pure returns (uint256 c);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`a`|`uint256`|First operand|
|`b`|`uint256`|Second operand|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`c`|`uint256`|Difference without underflow check|


### divUp

Division with rounding up


```solidity
function divUp(
    uint256 a,
    uint256 b
) internal pure returns (uint256 c);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`a`|`uint256`|Numerator|
|`b`|`uint256`|Denominator (must be non-zero)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`c`|`uint256`|Ceiling of a/b|


### min

Efficient min function


```solidity
function min(
    uint256 a,
    uint256 b
) internal pure returns (uint256 c);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`a`|`uint256`|First value|
|`b`|`uint256`|Second value|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`c`|`uint256`|Minimum of a and b|


### max

Efficient max function


```solidity
function max(
    uint256 a,
    uint256 b
) internal pure returns (uint256 c);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`a`|`uint256`|First value|
|`b`|`uint256`|Second value|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`c`|`uint256`|Maximum of a and b|


