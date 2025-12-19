# Echidna Fuzzing Tests

Property-based fuzzing tests for the RolesAuthority access control system.

## Installation

```bash
# Install Echidna (macOS)
brew install echidna

# Install Echidna (Linux)
pip install crytic-compile
wget https://github.com/crytic/echidna/releases/download/v2.2.1/echidna-2.2.1-Linux.zip
unzip echidna-2.2.1-Linux.zip
sudo mv echidna /usr/local/bin/

# Install Echidna (Docker)
docker pull trailofbits/echidna
```

## Running Tests

```bash
# Basic run
echidna echidna/EchidnaRolesTest.sol --contract EchidnaRolesTest --config echidna/echidna.yaml

# With coverage report
echidna echidna/EchidnaRolesTest.sol --contract EchidnaRolesTest --config echidna/echidna.yaml --format json > echidna-report.json

# Extended fuzzing (more iterations)
echidna echidna/EchidnaRolesTest.sol --contract EchidnaRolesTest --config echidna/echidna.yaml --test-limit 100000
```

## Properties Tested

### Invariants (echidna_* functions)

| Property | Description |
|----------|-------------|
| `echidna_no_privilege_escalation` | Attacker never gains any roles |
| `echidna_depositor_cannot_withdraw` | P0: VAULT_DEPOSITOR cannot call withdraw |
| `echidna_depositor_cannot_redeem` | P0: VAULT_DEPOSITOR cannot call redeem |
| `echidna_executor_no_whitelist` | Role separation: executor can't manage whitelists |
| `echidna_owner_is_admin` | Owner always retains ADMIN role |
| `echidna_guardian_can_pause` | Guardian maintains pause capability |

### Assertion Tests

| Function | Tests |
|----------|-------|
| `attacker_withdraw` | Attacker cannot withdraw |
| `attacker_grantRole` | Attacker cannot grant roles |
| `attacker_setCapability` | Attacker cannot modify capabilities |
| `attacker_pause` | Attacker cannot pause |
| `attacker_setWhitelist` | Attacker cannot modify whitelists |
| `depositor_withdraw` | P0: Depositor cannot withdraw |
| `depositor_redeem` | P0: Depositor cannot redeem |
| `executor_setWhitelist` | Executor cannot manage whitelists |

## Expected Output

```
echidna_no_privilege_escalation: passed! 🎉
echidna_depositor_cannot_withdraw: passed! 🎉
echidna_depositor_cannot_redeem: passed! 🎉
echidna_executor_no_whitelist: passed! 🎉
echidna_owner_is_admin: passed! 🎉
echidna_guardian_can_pause: passed! 🎉

Unique instructions: 1234
Unique codehashes: 5
Corpus size: 50000
```

## Coverage

After running, check `echidna-corpus/` for:
- `covered.*.txt` - Coverage data per contract
- `*.json` - Transaction sequences that triggered coverage

## Troubleshooting

### Compilation Errors

Ensure solc remappings match your project:
```bash
# Check current remappings
forge remappings

# Update echidna.yaml cryticArgs accordingly
```

### Slow Performance

Reduce test iterations or workers:
```yaml
testLimit: 10000
workers: 2
```

### Memory Issues

Limit sequence length:
```yaml
seqLen: 50
```
