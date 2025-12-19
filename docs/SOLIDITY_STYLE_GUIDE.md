# Solidity Style Guide

Coding conventions for the Superlib Arbitrage Protocol, based on the official Solidity Style Guide.

## Code Layout

### Indentation & Spacing

- **4 spaces** per indentation level (no tabs)
- **Two blank lines** between top-level declarations (contracts, interfaces, libraries)
- **One blank line** between function declarations within a contract
- **Maximum line length:** 120 characters

### File Structure Order

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// 1. Imports (grouped by source)
import {ERC4626} from "superlib/core/ERC4626.sol";
import {SafeTransferLib} from "superlib/transfer/SafeTransferLib.sol";

import {Roles} from "./roles/Roles.sol";

// 2. Interfaces
interface IFeeVault {
    // ...
}

// 3. Libraries
library FeeCalculator {
    // ...
}

// 4. Contracts
contract FeeVault is ERC4626 {
    // ...
}
```

### Contract Internal Order

```solidity
contract Example {
    // 1. Type declarations
    using SafeTransferLib for address;
    
    struct Config {
        uint256 maxFee;
        uint256 minDeposit;
    }
    
    enum Status { Pending, Active, Paused }
    
    // 2. State variables
    uint256 public constant MAX_FEE = 1000; // 10%
    uint256 public immutable deployTime;
    
    mapping(address => uint256) public balances;
    uint256 private _totalSupply;
    
    // 3. Events
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    
    // 4. Errors
    error InsufficientBalance();
    error Unauthorized();
    
    // 5. Modifiers
    modifier onlyAuthorized() {
        if (!authorized[msg.sender]) revert Unauthorized();
        _;
    }
    
    // 6. Functions (by visibility)
    constructor() { }
    
    receive() external payable { }
    fallback() external { }
    
    // External functions
    function deposit() external { }
    function withdraw() external { }
    
    // External view/pure
    function getBalance() external view returns (uint256) { }
    
    // Public functions
    function transfer() public { }
    
    // Internal functions
    function _beforeDeposit() internal { }
    
    // Private functions
    function _validateInput() private { }
}
```

## Naming Conventions

### Summary Table

| Type | Style | Example |
|------|-------|---------|
| Contract | CapWords | `FeeVault`, `FlashLoanEngine` |
| Library | CapWords | `SafeTransferLib`, `MathLib` |
| Interface | I + CapWords | `IFeeVault`, `IERC20` |
| Struct | CapWords | `UserConfig`, `SwapParams` |
| Enum | CapWords | `Status`, `Role` |
| Event | CapWords | `Deposit`, `RoleGranted` |
| Error | CapWords | `InsufficientBalance`, `Unauthorized` |
| Function | mixedCase | `deposit`, `getBalance`, `_internal` |
| Modifier | mixedCase | `onlyOwner`, `nonReentrant` |
| Variable | mixedCase | `totalSupply`, `userBalance` |
| Constant | UPPER_CASE | `MAX_FEE`, `ADMIN_ROLE` |
| Immutable | mixedCase or UPPER_CASE | `deployTime` or `DEPLOY_TIME` |
| Parameter | mixedCase | `amount`, `recipient`, `newOwner` |
| Private/Internal | _leading | `_balance`, `_transfer()` |

### Role Constants (Protocol Specific)

```solidity
library Roles {
    /// @notice Administrator role - full system control
    uint8 internal constant ADMIN = 0;
    
    /// @notice Executor role - can execute trades
    uint8 internal constant EXECUTOR = 1;
    
    /// @notice Arbitrage manager role - manages strategies
    uint8 internal constant ARBITRAGE_MANAGER = 2;
}
```

### Avoid These Names

- `l` (lowercase L) - looks like `1`
- `O` (uppercase O) - looks like `0`
- `I` (uppercase I) - looks like `1` or `l`

## Function Declarations

### Short Functions (Single Line OK)

```solidity
// ✅ Good - single statement
function owner() external view returns (address) { return _owner; }

// ✅ Good - simple getter
function balanceOf(address user) external view returns (uint256) {
    return balances[user];
}
```

### Long Functions

```solidity
// ✅ Good - each argument on its own line
function thisFunctionHasLotsOfArguments(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 minAmountOut,
    address recipient
)
    external
    nonReentrant
    returns (uint256 amountOut)
{
    // Implementation
}

// ❌ Bad - arguments not aligned
function thisFunctionHasLotsOfArguments(address tokenIn, address tokenOut,
    uint256 amountIn, uint256 minAmountOut, address recipient)
    external nonReentrant returns (uint256) {
    // Implementation
}
```

### Modifier Order

```
visibility → mutability → virtual → override → custom modifiers
```

```solidity
// ✅ Good
function transfer(address to, uint256 amount)
    public
    virtual
    override
    nonReentrant
    returns (bool)
{
    // ...
}

// ❌ Bad - wrong order
function transfer(address to, uint256 amount)
    nonReentrant
    override
    public
    virtual
    returns (bool)
{
    // ...
}
```

## Control Structures

### Braces

```solidity
// ✅ Good - opening brace on same line
if (condition) {
    doSomething();
}

// ❌ Bad - opening brace on new line
if (condition)
{
    doSomething();
}
```

### If/Else

```solidity
// ✅ Good - else on same line as closing brace
if (x < 10) {
    x += 1;
} else if (x > 100) {
    x -= 1;
} else {
    x = 50;
}

// ❌ Bad
if (x < 10) {
    x += 1;
}
else {
    x -= 1;
}
```

### Single Statement (Braces Optional)

```solidity
// ✅ OK for truly single statements
if (x < 10)
    x += 1;

// ✅ Also OK with braces
if (x < 10) {
    x += 1;
}

// ❌ Bad - multi-line without braces
if (x < 10)
    someArray.push(Item({
        name: "test",
        value: 42
    }));
```

## Whitespace

### Operators

```solidity
// ✅ Good - spaces around operators
x = 1;
y = 2;
z = (a + b) * (c - d);

// ✅ Good - no space for precedence
x = 2**3 + 5;
x = a*b + c*d;

// ❌ Bad - inconsistent spacing
x=1;
y = a+b;
z = a *b;
```

### Mappings

```solidity
// ✅ Good - no space after mapping
mapping(address => uint256) public balances;
mapping(address => mapping(address => uint256)) public allowances;

// ❌ Bad
mapping (address => uint256) public balances;
mapping( address => uint256 ) public balances;
```

### Arrays

```solidity
// ✅ Good
uint256[] public values;
address[] memory recipients;

// ❌ Bad
uint256 [] public values;
```

### Function Calls

```solidity
// ✅ Good - no space inside parentheses
transfer(recipient, amount);
balances[user] = newBalance;

// ❌ Bad
transfer( recipient, amount );
balances[ user ] = newBalance;
```

## NatSpec Documentation

### Required Tags

```solidity
/// @title FeeVault
/// @author Superlib Arbitrage Protocol Team
/// @notice ERC4626 vault for collecting and distributing protocol fees
/// @dev Inherits from Superlib ERC4626 with RolesAuthority access control
contract FeeVault is ERC4626 {
    
    /// @notice Deposit assets and mint shares
    /// @dev Implements ERC4626 deposit with access control
    /// @param assets Amount of underlying tokens to deposit
    /// @param receiver Address to receive the minted shares
    /// @return shares Amount of shares minted
    /// @custom:security Requires VAULT_DEPOSITOR role
    function deposit(uint256 assets, address receiver)
        public
        override
        returns (uint256 shares)
    {
        // ...
    }
}
```

### Custom Tags (Protocol Specific)

```solidity
/// @custom:security Requires ADMIN role
/// @custom:audit Verified in P0 tests
/// @custom:gas ~50,000 gas
```

## Error Handling

### Custom Errors (Preferred)

```solidity
// ✅ Good - custom errors (gas efficient)
error InsufficientBalance(uint256 available, uint256 required);
error Unauthorized(address caller, bytes4 selector);

function withdraw(uint256 amount) external {
    if (balances[msg.sender] < amount) {
        revert InsufficientBalance(balances[msg.sender], amount);
    }
}

// ❌ Avoid - require with string (expensive)
function withdraw(uint256 amount) external {
    require(balances[msg.sender] >= amount, "Insufficient balance");
}
```

### Error Naming

- Use CapWords style
- Be descriptive: `InsufficientBalance` not `Error1`
- Include relevant parameters

## Events

```solidity
// ✅ Good - indexed parameters for filtering
event Transfer(
    address indexed from,
    address indexed to,
    uint256 amount
);

event RoleGranted(
    address indexed user,
    uint8 indexed role,
    address indexed grantor
);

// Emit with same parameter names
emit Transfer(from, to, amount);
```

## Assembly / Yul

```solidity
// ✅ Good - documented assembly
function hasRole(bytes32 roles, uint8 role) internal pure returns (bool has) {
    /// @solidity memory-safe-assembly
    assembly {
        // (roles >> role) & 1
        has := and(shr(role, roles), 1)
    }
}

// ✅ Good - separate complex assembly into library
library YulHelpers {
    /// @notice Check if role bit is set
    /// @dev Uses bitwise operations - manual audit required
    function hasRole(bytes32 roles, uint8 role) internal pure returns (bool has) {
        assembly {
            has := and(shr(role, roles), 1)
        }
    }
}
```

## Import Style

```solidity
// ✅ Good - named imports (explicit, tree-shakeable)
import {ERC4626} from "superlib/core/ERC4626.sol";
import {SafeTransferLib} from "superlib/transfer/SafeTransferLib.sol";
import {RolesAuthority} from "superlib/auth/RolesAuthority.sol";

// ❌ Avoid - wildcard imports (implicit, larger bytecode)
import "superlib/core/ERC4626.sol";
import * as Superlib from "superlib/";
```

## Gas Optimization Style

```solidity
// ✅ Good - cache storage reads
function process(uint256[] calldata ids) external {
    uint256 len = ids.length; // Cache length
    uint256 total = totalSupply; // Cache storage
    
    for (uint256 i; i < len; ) {
        // Use cached values
        unchecked { ++i; }
    }
    
    totalSupply = total; // Single storage write
}

// ❌ Bad - repeated storage reads
function process(uint256[] calldata ids) external {
    for (uint256 i = 0; i < ids.length; i++) {
        totalSupply += amounts[i]; // Storage read/write each iteration
    }
}
```

## Testing Style

```solidity
contract FeeVaultTest is Test {
    // Use descriptive test names
    function test_deposit_success() public { }
    function test_deposit_revertsWhenPaused() public { }
    function test_withdraw_onlyAdmin() public { }
    
    // Invariant test naming
    function invariant_totalSharesMatchDeposits() public { }
    
    // Fuzz test naming
    function testFuzz_deposit(uint256 amount) public { }
}
```

## Formatter Configuration

```toml
# foundry.toml
[fmt]
line_length = 120
tab_width = 4
bracket_spacing = false
int_types = "long"
multiline_func_header = "params_first"
quote_style = "double"
number_underscore = "thousands"
single_line_statement_blocks = "preserve"
```

## Checklist

Before committing:

- [ ] All public functions have NatSpec
- [ ] Custom errors used (not require strings)
- [ ] Named imports (not wildcards)
- [ ] Consistent naming conventions
- [ ] No trailing whitespace
- [ ] 4-space indentation
- [ ] Max 120 char lines
- [ ] Functions ordered by visibility
- [ ] Events indexed appropriately
- [ ] Assembly documented with `@solidity memory-safe-assembly`

Run formatter:
```bash
forge fmt
forge fmt --check  # CI check
```
