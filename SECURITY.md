# Security Testing Suite

Comprehensive security analysis for the Superlib Arbitrage Protocol.

## Quick Start

```bash
# Install all security tools
pip install -r requirements.txt
npm install

# Run all security checks
npm run security:full
```

## Testing Layers

### 1. Unit Tests (Foundry)
```bash
npm run test:unit        # 16 role-based tests
npm run test:security    # Attacker/escalation tests
```

### 2. Invariant Fuzzing (Foundry)
```bash
npm run test:invariant   # 10 property-based tests (256 runs)
npm run test:fuzz        # Extended fuzzing (1000 runs)
```

### 3. Property Fuzzing (Echidna)
```bash
npm run echidna          # 50,000 iterations
npm run echidna:long     # 100,000 iterations
```

### 4. Static Analysis (Slither)
```bash
npm run slither
```

### 5. Symbolic Execution (Mythril)
```bash
npm run mythril:access   # Targeted access control analysis
npm run mythril:full     # Full protocol analysis
```

### 6. Formal Verification (Z3 SMT)
```bash
npm run smt              # Python Z3 verification
```

### 7. Solidity SMTChecker (Native)
```bash
npm run smt:solc         # Full SMTChecker analysis
npm run smt:chc          # CHC engine (multi-transaction)
npm run smt:bmc          # BMC engine (single function)
```

## Security Properties Verified

### P0 - Critical (Audit Fixes)

| Property | Test Coverage |
|----------|---------------|
| VAULT_DEPOSITOR cannot withdraw | Unit, Invariant, Echidna, SMT |
| VAULT_DEPOSITOR cannot redeem | Unit, Invariant, Echidna |
| Missing function bindings fixed | Unit |
| Whitelist admin elevation | Unit, Echidna |

### P1 - High (Audit Fixes)

| Property | Test Coverage |
|----------|---------------|
| Guardian can pause | Unit, Invariant |
| Fee updater cannot pause | Unit, Invariant |
| Role separation enforced | Invariant, Echidna |

### Core Invariants

| Invariant | Verification Method |
|-----------|---------------------|
| No privilege escalation | Foundry Invariant, Echidna, SMT |
| Owner retains ADMIN | Foundry Invariant, SMT |
| Attacker has no roles | Foundry Invariant, Echidna |
| Role bits are independent | SMT |
| canCall requires role AND capability | SMT |

## Tool Configuration

### Slither
- Config: `slither.config.json`
- Excludes: naming-convention, solc-version, test files

### Echidna
- Config: `echidna/echidna.yaml`
- 50,000 iterations, 100 tx sequence length
- 6 invariant properties, 11 assertion tests

### Mythril
- Config: `mythril.config.json`
- Targets: SWC-105, SWC-107, SWC-115, SWC-124
- 300s timeout, depth 50

### Z3 SMT
- Script: `scripts/smt_verify.py`
- Proves: role assignment, capability checks, P0 invariants

## CI Integration

```yaml
# .github/workflows/security.yml
name: Security
on: [push, pull_request]
jobs:
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: foundry-rs/foundry-toolchain@v1
      
      - name: Install Python deps
        run: pip install -r requirements.txt
        
      - name: Foundry Tests
        run: forge test
        
      - name: Slither
        run: slither . --config-file slither.config.json
        continue-on-error: true
        
      - name: SMT Verification
        run: python scripts/smt_verify.py
```

## SWC Reference

| SWC ID | Name | Severity | Checked By |
|--------|------|----------|------------|
| SWC-101 | Integer Overflow | High | Solidity 0.8+ |
| SWC-104 | Unchecked Return | Medium | Slither |
| SWC-105 | Unprotected Withdrawal | Critical | Mythril |
| SWC-106 | Unprotected SELFDESTRUCT | Critical | Mythril |
| SWC-107 | Reentrancy | Critical | Slither, Mythril |
| SWC-115 | tx.origin Auth | High | Slither, Mythril |
| SWC-116 | Timestamp Dependence | Low | Slither |
| SWC-124 | Arbitrary Storage | Critical | Mythril |

## Audit Status

- **Trinity Audit**: All P0/P1 findings addressed
- **Foundry Tests**: 26/26 passing
- **Echidna**: 6 invariants proven (50k+ calls)
- **SMT**: 5 properties formally verified
