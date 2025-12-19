# Mythril Security Analysis

Symbolic execution analysis for detecting vulnerabilities in the protocol contracts.

## Installation

```bash
# Install Mythril
pip install mythril

# Or via Docker
docker pull mythril/myth
```

## Running Analysis

### Full Analysis (All Contracts)

```bash
# Run comprehensive analysis
./mythril/analyze.sh

# Or via npm
npm run mythril:full
```

### Targeted Analysis (Access Control Focus)

```bash
# Run Python-based targeted analysis
python mythril/targeted_analysis.py

# Or via npm
npm run mythril:access
```

### Single Contract Analysis

```bash
# Analyze specific contract
myth analyze src/FeeVault.sol \
  --solc-json mythril/mythril.config.json \
  --solv 0.8.28 \
  --execution-timeout 300 \
  -o text
```

## Analysis Targets

### P0 Priority (Audit Fixes)

| Contract | Functions | Risk |
|----------|-----------|------|
| FeeVault | `withdraw`, `redeem`, `emergencyWithdraw` | Unauthorized withdrawal |
| RolesAuthority | `setUserRole`, `setRoleCapability` | Privilege escalation |
| MEVProtector | `setTargetWhitelist`, `setSelectorWhitelist` | Whitelist bypass |
| FlashLoanEngine | `executeFlashLoanArbitrage`, `setDexRouterWhitelist` | Flash loan exploit |
| CrossChainRouter | `queueChainConfig`, `executeChainConfig` | Timelock bypass |

### Critical SWC IDs

| SWC | Name | Severity |
|-----|------|----------|
| SWC-101 | Integer Overflow/Underflow | High |
| SWC-104 | Unchecked Call Return Value | Medium |
| SWC-105 | Unprotected Ether Withdrawal | Critical |
| SWC-106 | Unprotected SELFDESTRUCT | Critical |
| SWC-107 | Reentrancy | Critical |
| SWC-115 | Authorization through tx.origin | High |
| SWC-116 | Timestamp Dependence | Low |
| SWC-124 | Write to Arbitrary Storage | Critical |

## Expected Results

For a properly secured protocol, Mythril should report:

```
✅ No issues found in FeeVault
✅ No issues found in RolesAuthority
✅ No issues found in MEVProtector
✅ No issues found in FlashLoanEngine
✅ No issues found in CrossChainRouter
```

### Common False Positives

1. **SWC-107 (Reentrancy)** in view functions - Safe, no state changes
2. **SWC-116 (Timestamp)** in timelock - Expected behavior
3. **SWC-104 (Unchecked Return)** with SafeTransferLib - Already handled

## Report Format

Reports are saved to `mythril/reports/`:

- `{ContractName}.json` - Machine-readable JSON
- `{ContractName}.txt` - Human-readable text
- `access_control_audit.json` - Targeted analysis summary

### JSON Report Structure

```json
{
  "issues": [
    {
      "swc-id": "SWC-107",
      "title": "Reentrancy",
      "description": {
        "head": "...",
        "tail": "..."
      },
      "severity": "High",
      "locations": [
        {
          "sourceMap": "123:45:0"
        }
      ]
    }
  ]
}
```

## Configuration

### mythril.config.json

```json
{
  "remappings": [
    "forge-std/=lib/forge-std/src/",
    "superlib/=lib/superlib/"
  ],
  "optimizer": {
    "enabled": true,
    "runs": 200
  },
  "evmVersion": "paris"
}
```

### Analysis Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--execution-timeout` | 300 | Seconds per contract |
| `--max-depth` | 50 | Call stack depth |
| `--strategy` | bfs | Search strategy (bfs/dfs/naive) |
| `--solv` | 0.8.28 | Solidity version |

## Troubleshooting

### Compilation Errors

```bash
# Ensure solc version is correct
solc-select install 0.8.28
solc-select use 0.8.28

# Verify remappings
forge remappings
```

### Timeout Issues

```bash
# Reduce depth for large contracts
myth analyze src/FeeVault.sol --max-depth 30 --execution-timeout 600
```

### Memory Issues

```bash
# Use Docker with memory limits
docker run -m 8g mythril/myth analyze ...
```

## Integration with CI

```yaml
# .github/workflows/security.yml
- name: Run Mythril
  run: |
    pip install mythril
    ./mythril/analyze.sh
  continue-on-error: true
```
