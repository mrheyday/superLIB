# Contributing to SuperLIB

Thank you for your interest in contributing! This document provides guidelines and standards for contributing to the SuperLIB protocol.

## Development Setup

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Node.js](https://nodejs.org/) >= 18.0.0
- [Git](https://git-scm.com/)

### Installation

```bash
# Clone the repository
git clone https://github.com/mrheyday/superLIB.git
cd superLIB

# Install Foundry dependencies
forge install

# Install Node.js dependencies (for linting tools)
npm install

# Set up git hooks
npm run prepare

# Build and test
forge build
forge test
```

## Code Style Guide

### Solidity Style

We follow the [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html) with these additions:

#### Formatting

- **Line length**: 120 characters max
- **Indentation**: 4 spaces (no tabs)
- **Bracket spacing**: No spaces inside brackets
- **Quotes**: Double quotes for strings

Run `forge fmt` to auto-format your code.

#### Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Contracts | PascalCase | `FeeVault` |
| Interfaces | IPascalCase | `IFlashLoanReceiver` |
| Libraries | PascalCase | `SafeTransferLib` |
| Functions | camelCase | `executeArbitrage` |
| Variables | camelCase | `totalSupply` |
| Constants | SCREAMING_SNAKE_CASE | `MAX_FEE_BPS` |
| Immutables | SCREAMING_SNAKE_CASE | `ORIGINAL_OWNER` |
| Events | PascalCase | `ArbitrageExecuted` |
| Errors | PascalCase | `PoolNotWhitelisted` |
| Modifiers | camelCase | `nonReentrant` |
| Enums | PascalCase | `StrategyType` |
| Struct | PascalCase | `SwapInstruction` |

#### Contract Layout

Follow this order within contracts:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Imports (sorted alphabetically by path)
import {Contract} from "path/Contract.sol";

/// @title ContractName
/// @notice Brief description
/// @dev Implementation details
/// @custom:security-contact security@example.com
contract ContractName {
    // 1. Type declarations (using, struct, enum)
    // 2. Constants
    // 3. Immutables
    // 4. State variables
    // 5. Events
    // 6. Errors
    // 7. Modifiers
    // 8. Constructor
    // 9. Receive/Fallback
    // 10. External functions
    // 11. Public functions
    // 12. Internal functions
    // 13. Private functions
    // 14. View/Pure functions
}
```

#### NatSpec Documentation

All public/external functions must have NatSpec:

```solidity
/// @notice Execute an arbitrage trade via flash loan
/// @dev Calls whitelisted DEX routers with slippage protection
/// @param flashLoanPool The pool to borrow from
/// @param token The token to borrow
/// @param swaps Array of swap instructions
/// @return profit Net profit after fees
/// @custom:security Validates all routers are whitelisted
function executeArbitrage(
    address flashLoanPool,
    address token,
    SwapInstruction[] calldata swaps
) external returns (uint256 profit) {
```

### Security Patterns

#### Required Patterns

1. **Checks-Effects-Interactions (CEI)**
   ```solidity
   // 1. Checks
   if (amount == 0) revert ZeroAmount();
   
   // 2. Effects
   balances[msg.sender] -= amount;
   
   // 3. Interactions
   token.safeTransfer(msg.sender, amount);
   ```

2. **Reentrancy Protection**
   - Use `nonReentrant` modifier on state-changing external functions
   - Use dedicated locks for complex flows (e.g., `_inFlashLoan`)

3. **Access Control**
   - Use `requiresAuth` from RolesAuthority
   - Follow least-privilege principle

4. **Input Validation**
   - Validate all external inputs
   - Check for zero addresses
   - Validate array bounds

#### Forbidden Patterns

- ❌ `tx.origin` for authentication
- ❌ `selfdestruct` / `suicide`
- ❌ Arbitrary `delegatecall`
- ❌ Unchecked low-level calls
- ❌ `block.timestamp` for randomness
- ❌ Floating pragma (use exact version)

### Testing Requirements

#### Coverage Requirements

- Minimum 80% line coverage
- 100% coverage for security-critical functions
- All public/external functions must have tests

#### Test Categories

1. **Unit Tests** (`test/unit/`)
   - Test individual functions in isolation
   - Mock dependencies

2. **Integration Tests** (`test/integration/`)
   - Test contract interactions
   - Use fork tests for external protocols

3. **Invariant Tests** (`test/invariant/`)
   - Define and test protocol invariants
   - Use fuzzing for edge cases

#### Test Naming

```solidity
function test_FunctionName_SpecificScenario() public {
    // Arrange
    // Act
    // Assert
}

function testRevert_FunctionName_WhenCondition() public {
    // Should revert with specific error
}

function testFuzz_FunctionName(uint256 amount) public {
    // Fuzz test
}
```

## Git Workflow

### Branch Naming

- `feature/description` - New features
- `fix/description` - Bug fixes
- `security/description` - Security patches
- `docs/description` - Documentation updates
- `refactor/description` - Code refactoring

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): description

[optional body]

[optional footer]
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `security`

Examples:
```
feat(vault): add dead shares initialization protection
fix(arbitrage): validate initiator in flash loan callback
security(engine): replace arbitrary call with structured swaps
docs(readme): update security audit status
test(roles): add invariant tests for role separation
```

### Pull Request Process

1. Create a feature branch from `main`
2. Make your changes following the style guide
3. Ensure all tests pass: `forge test`
4. Ensure formatting: `forge fmt --check`
5. Update documentation if needed
6. Create a PR with a clear description
7. Address review feedback
8. Squash and merge when approved

### Pre-commit Checks

The following checks run automatically:

- ✅ Code formatting (`forge fmt`)
- ✅ Linting (`forge lint`, `solhint`)
- ✅ Build (`forge build`)
- ✅ Tests (`forge test`)
- ✅ Security pattern check

## Security

### Reporting Vulnerabilities

**DO NOT** open public issues for security vulnerabilities.

Email: security@[domain].com

See [SECURITY.md](SECURITY.md) for our security policy.

### Security Review Checklist

Before submitting security-sensitive changes:

- [ ] No arbitrary external calls with user data
- [ ] Reentrancy protection on state-changing functions
- [ ] Access control on privileged functions
- [ ] Input validation on all parameters
- [ ] Safe math operations
- [ ] Event emission for state changes
- [ ] NatSpec documentation complete

## Questions?

- Open a [GitHub Discussion](https://github.com/mrheyday/superLIB/discussions)
- Check existing issues and PRs

Thank you for contributing! 🚀
