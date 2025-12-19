# Testing Guide

This guide explains the test suite structure, how to run tests, and how to write new tests for the protocol.

## Test Suite Overview

The test suite validates all security mechanisms and functional requirements of the protocol. Tests are organized by contract and concern, with dedicated files for attack vector validation and integration scenarios.

### Test Files

The `test/BaseTest.sol` file provides common infrastructure for all tests including test accounts, mock tokens, and helper functions. All test contracts inherit from BaseTest to access this shared functionality.

The `test/FeeVault.t.sol` file contains 21 tests covering the vault's deposit and withdrawal mechanics, fee calculations, reward distribution, and inflation attack prevention.

The `test/MEVProtector.t.sol` file contains 14 tests validating the commit-reveal scheme, target and selector whitelisting, timing constraints, and access controls.

The `test/MaximumSecurityEngine.t.sol` file contains 16 tests for rate limiting, security score calculations, whitelist enforcement, and access control validation.

The `test/FlashLoanEngine.t.sol` file contains 12 tests covering provider management, DEX router whitelisting, fee validation, and execution authorization.

The `test/UltimateArbitrageEngine.t.sol` file contains 16 tests for flash loan pool whitelisting, profit verification through balance snapshots, and authorized executor validation.

The `test/CrossChainRouter.t.sol` file contains 14 tests validating the 24-hour timelock for configuration changes, daily volume limits, and amount range validation.

The `test/QuantumContracts.t.sol` file contains 11 tests for engine update timelocks and authorization mechanisms.

The `test/StrategyContracts.t.sol` file contains 8 tests for strategy limits, pagination, and analytics access control.

The `test/RiskAndStrategy.t.sol` file contains 10 tests for risk score calculations, bounds checking, and batch operations.

The `test/AttackVectors.t.sol` file contains 9 tests specifically designed to verify that known attack patterns are blocked.

The `test/Integration.t.sol` file contains 5 tests validating multi-contract workflows and end-to-end scenarios.

## Running Tests

### Basic Test Execution

Run all tests with the command `forge test`. This executes every test function in the test directory and reports pass or fail status for each.

### Verbose Output

For debugging, use `forge test -vvv` to see detailed output including call traces and revert reasons. The verbosity flag accepts values from `-v` to `-vvvvv` with increasing detail at each level.

### Targeting Specific Tests

Run tests in a specific file using `forge test --match-path test/FeeVault.t.sol`. Run a specific test function using `forge test --match-test test_inflationAttack_prevented`. Combine both to run a specific test in a specific file.

### Gas Reporting

Generate a gas report showing the gas cost of each function call using `forge test --gas-report`. This helps identify expensive operations that might benefit from optimization.

### Fuzz Testing

The test suite includes fuzz tests that run with randomized inputs. By default, fuzz tests run 256 times. Increase this for more thorough testing using `FOUNDRY_FUZZ_RUNS=1000 forge test`. For CI pipelines, consider even higher values such as 10000 runs.

### Coverage Analysis

Generate a coverage report showing which lines of code are exercised by tests using `forge coverage`. The output shows coverage percentages by file and highlights uncovered lines.

## Writing New Tests

### Test Structure

Each test function should follow a clear pattern: arrange the test conditions, act by calling the function under test, then assert the expected outcomes. Use descriptive function names that explain what is being tested.

A typical test function looks like this:

```solidity
function test_deposit_withValidAmount_mintsCorrectShares() public {
    // Arrange
    uint256 depositAmount = 10000e6;
    uint256 expectedShares = vault.previewDeposit(depositAmount);
    
    // Act
    vm.prank(alice);
    uint256 actualShares = vault.deposit(depositAmount, alice);
    
    // Assert
    assertEq(actualShares, expectedShares, "Shares mismatch");
    assertEq(vault.balanceOf(alice), actualShares, "Balance not updated");
}
```

### Testing Reverts

To test that a function reverts with a specific error, use the `vm.expectRevert` cheatcode before calling the function:

```solidity
function test_deposit_withZeroAmount_reverts() public {
    vm.prank(alice);
    vm.expectRevert(FeeVault.ZeroAmount.selector);
    vault.deposit(0, alice);
}
```

For errors with parameters, encode the full error:

```solidity
function test_deposit_belowMinimum_reverts() public {
    uint256 smallAmount = 100;
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(
        FeeVault.DepositTooSmall.selector,
        smallAmount,
        vault.MINIMUM_DEPOSIT()
    ));
    vault.deposit(smallAmount, alice);
}
```

### Testing Events

To verify that events are emitted correctly, use `vm.expectEmit`:

```solidity
function test_deposit_emitsEvent() public {
    vm.expectEmit(true, true, false, true);
    emit Deposit(alice, alice, 10000e6, expectedShares);
    
    vm.prank(alice);
    vault.deposit(10000e6, alice);
}
```

### Fuzz Tests

Fuzz tests accept random parameters generated by the fuzzer:

```solidity
function testFuzz_deposit_anyValidAmount(uint256 amount) public {
    // Bound the input to valid range
    amount = bound(amount, vault.MINIMUM_DEPOSIT(), type(uint128).max);
    
    // Fund the test account
    deal(address(usdc), alice, amount);
    
    vm.startPrank(alice);
    usdc.approve(address(vault), amount);
    
    uint256 shares = vault.deposit(amount, alice);
    
    // Verify invariants
    assertTrue(shares > 0, "Should receive shares");
    assertEq(vault.balanceOf(alice), shares, "Balance mismatch");
    vm.stopPrank();
}
```

### Helper Functions

The BaseTest contract provides several helper functions. The `_fundAccount` function mints tokens to a specified address. The `_approveAll` function approves a spender for all test tokens. The `_advanceTime` function moves the block timestamp forward. The `_advanceBlocks` function moves the block number forward.

### Testing Access Control

Many functions are restricted to specific roles. Test both authorized and unauthorized callers:

```solidity
function test_setFee_asOwner_succeeds() public {
    vm.prank(owner);
    vault.setDepositFee(100);
    assertEq(vault.depositFee(), 100);
}

function test_setFee_asNonOwner_reverts() public {
    vm.prank(alice);
    vm.expectRevert("Ownable: caller is not the owner");
    vault.setDepositFee(100);
}
```

### Testing Timelocks

For timelock-protected functions, test both the queuing and execution phases:

```solidity
function test_chainConfig_respectsTimelock() public {
    // Queue the configuration
    vm.prank(owner);
    router.queueChainConfig(137, bridgeAddress, 1000, 1000000, true);
    
    // Attempt immediate execution (should fail)
    vm.expectRevert(CrossChainRouter.ConfigTimelockActive.selector);
    router.executeChainConfig(137);
    
    // Advance time past timelock
    vm.warp(block.timestamp + 25 hours);
    
    // Now execution should succeed
    router.executeChainConfig(137);
    
    // Verify configuration applied
    (address bridge,,, bool active) = router.chainConfigs(137);
    assertEq(bridge, bridgeAddress);
    assertTrue(active);
}
```

## Test Categories

### Unit Tests

Unit tests validate individual functions in isolation. Each public and external function should have tests covering the success path, all failure modes with correct error messages, edge cases such as boundary values, and state changes including storage updates and events.

### Integration Tests

Integration tests validate interactions between multiple contracts. These tests verify that the contracts work correctly together and that authorization flows properly across contract boundaries.

### Attack Vector Tests

Attack vector tests specifically attempt known exploit patterns to verify they are blocked. These tests should be updated whenever new attack techniques are discovered in the DeFi ecosystem.

### Invariant Tests

Invariant tests define properties that must always hold true and use fuzzing to search for violations. Examples include the requirement that total shares always equal the sum of individual balances and that vault assets always cover share redemptions.

## Continuous Integration

The test suite is designed to run in CI pipelines. Configure your CI to run `forge test` on every pull request. Consider running extended fuzz tests on merge to main using increased run counts. Generate and track coverage reports to ensure coverage does not decrease.
