# SMTChecker Formal Verification Guide

Mathematical proofs for the RolesAuthority access control system using Solidity's built-in SMTChecker.

## Overview

The SMTChecker uses **SMT (Satisfiability Modulo Theories)** and **Horn clause solving** to mathematically prove properties about the contract's behavior across **all possible inputs** and **multiple transactions**.

### Engines

| Engine | Scope | Use Case |
|--------|-------|----------|
| **CHC** (Constrained Horn Clauses) | Multi-transaction, state properties | Prove invariants hold forever |
| **BMC** (Bounded Model Checker) | Single function, local properties | Find bugs in specific functions |

## Running Verification

### Quick Start

```bash
# Run full CHC verification (recommended)
npm run smt:chc

# Run BMC for overflow/underflow checks
npm run smt:bmc

# Run both engines
npm run smt:solc
```

### Manual Commands

```bash
# CHC engine - proves state properties across unbounded transactions
solc src/RolesAuthorityVerified.sol \
    --base-path . \
    --include-path lib/superlib \
    --include-path lib/forge-std/src \
    --model-checker-engine chc \
    --model-checker-targets assert \
    --model-checker-timeout 60000 \
    --model-checker-show-proved-safe \
    --model-checker-show-unproved

# BMC engine - finds local bugs in functions
solc src/RolesAuthorityVerified.sol \
    --base-path . \
    --include-path lib/superlib \
    --include-path lib/forge-std/src \
    --model-checker-engine bmc \
    --model-checker-targets assert,underflow,overflow \
    --model-checker-timeout 30000
```

## Verification Targets

### P0 Audit Fixes (Critical)

| Property | Function | Assertion |
|----------|----------|-----------|
| VAULT_DEPOSITOR cannot withdraw | `verifyP0_DepositorCannotWithdraw` | `withdrawCap & DEPOSITOR_BIT == 0` |
| VAULT_DEPOSITOR cannot redeem | `verifyP0_DepositorCannotRedeem` | `redeemCap & DEPOSITOR_BIT == 0` |
| Only ADMIN/GUARDIAN can pause | `verifyP0_PauseRestriction` | `pauseCap & ~(ADMIN\|GUARDIAN) == 0` |

### P1 Role Separation (High)

| Property | Function | Assertion |
|----------|----------|-----------|
| EXECUTOR cannot modify whitelists | `verifyP1_ExecutorNoWhitelist` | `whitelistCap & EXECUTOR_BIT == 0` |
| FEE_UPDATER cannot pause | `verifyP1_FeeUpdaterNoPause` | `pauseCap & FEE_UPDATER_BIT == 0` |
| ARBITRAGE_MANAGER cannot withdraw | `verifyP1_ArbitrageManagerNoWithdraw` | `withdrawCap & ARB_MANAGER_BIT == 0` |

### State Properties (CHC)

| Invariant | Description | Multi-TX |
|-----------|-------------|----------|
| Blacklist permanence | Blacklisted users NEVER gain roles | ✅ |
| Role bit correctness | `setUserRole` correctly modifies bitmask | ✅ |
| Zero-role restriction | Users with no roles can only call public functions | ✅ |
| Ownership non-zero | `owner` is never `address(0)` | ✅ |

## Understanding Results

### Success Output

```
Info: CHC: 12 verification condition(s) proved safe.
```

This means the SMTChecker **mathematically proved** all assertions hold for:
- All possible input values
- All possible transaction sequences
- All possible block states

### Failure Output

```
Warning: CHC: Assertion violation happens here.
Counterexample:
x = 42, user = 0x1234...

Transaction trace:
Contract.constructor()
State: x = 0
Contract.setUserRole(0x1234, 7, true)
State: x = 42
Contract.verifyP0_DepositorCannotWithdraw()
```

The counterexample shows **exactly** how to violate the property.

### Unproved Output

```
Warning: CHC: Assertion violation might happen here.
```

This means the solver couldn't prove OR disprove within the timeout. Options:
1. Increase timeout: `--model-checker-timeout 120000`
2. Simplify the property
3. Add more `require` statements as hints

## Verification Contract Design

### Adversary Modeling

```solidity
mapping(address => bool) public isBlacklisted;

function setUserRole(address user, uint8 role, bool enabled) {
    if (enabled) {
        require(!isBlacklisted[user], "USER_BLACKLISTED");
    }
    super.setUserRole(user, role, enabled);
    
    // CHC proves this holds forever, across all transactions
    assert(!isBlacklisted[user] || getUserRoles[user] == bytes32(0));
}
```

The `isBlacklisted` mapping models an **adversary** - the SMTChecker proves that no sequence of transactions can give a blacklisted address any roles.

### Capability Verification Pattern

```solidity
function verifyP0_DepositorCannotWithdraw(
    address vaultAddress,
    bytes4 withdrawSelector
) external view {
    bytes32 withdrawCap = getRolesWithCapability[vaultAddress][withdrawSelector];
    uint256 depositorBit = uint256(1) << Roles.VAULT_DEPOSITOR;
    
    // SMT proves: VAULT_DEPOSITOR bit is NEVER set in withdraw capability
    assert(uint256(withdrawCap) & depositorBit == 0);
}
```

### Reentrancy Analysis (CHC)

```solidity
function simulateExternalCall(address target) external {
    bytes32 preRoles = getUserRoles[msg.sender];
    
    // CHC assumes target.call() can do ANYTHING including reenter
    (bool success,) = target.call("");
    
    // CHC proves this holds even with reentrancy
    // (because only owner can modify roles)
    assert(getUserRoles[msg.sender] == preRoles || msg.sender == owner);
}
```

## Solver Requirements

### z3 (Recommended)

```bash
# macOS
brew install z3

# Ubuntu
apt install z3

# Verify
z3 --version
```

### Eldarica (Alternative CHC Solver)

```bash
# Download from https://github.com/uuverifiers/eldarica
# Add to PATH
export PATH=$PATH:/path/to/eldarica

# Run with Eldarica
solc --model-checker-solvers eld ...
```

## Tuning Options

### Timeout

```bash
# 60 seconds (default)
--model-checker-timeout 60000

# 5 minutes for complex contracts
--model-checker-timeout 300000
```

### Targets

```bash
# Assertions only (fastest)
--model-checker-targets assert

# All checks
--model-checker-targets assert,underflow,overflow,divByZero

# Arithmetic only
--model-checker-targets underflow,overflow
```

### Specific Contracts

```bash
# Only verify RolesAuthorityVerified
--model-checker-contracts "src/RolesAuthorityVerified.sol:RolesAuthorityVerified"
```

## Integration with CI

```yaml
# .github/workflows/formal-verification.yml
name: Formal Verification
on: [push, pull_request]

jobs:
  smt:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install solc
        run: |
          pip install solc-select
          solc-select install 0.8.28
          solc-select use 0.8.28
          
      - name: Install z3
        run: apt-get install -y z3
        
      - name: Run SMTChecker
        run: npm run smt:chc
        timeout-minutes: 10
```

## Limitations

1. **Loops**: CHC handles loops, BMC may need loop unrolling hints
2. **External calls**: Modeled as arbitrary behavior (conservative)
3. **Assembly**: Abstracted - may cause false positives
4. **Complex math**: `ecrecover`, `keccak256` are uninterpreted functions

## References

- [Solidity SMTChecker Docs](https://docs.soliditylang.org/en/latest/smtchecker.html)
- [SMT-based Verification Paper](https://github.com/leonardoalt/text/blob/master/solidity_isola_2018/main.pdf)
- [z3 Theorem Prover](https://github.com/Z3Prover/z3)
