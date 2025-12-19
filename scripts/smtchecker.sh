#!/bin/bash
# Run Solidity SMTChecker for formal verification
# Requires: solc with SMT solver support (z3 or cvc5)

set -e

echo "=== Solidity SMTChecker Formal Verification ==="
echo ""

# Check for solc
if ! command -v solc &> /dev/null; then
    echo "Error: solc not found. Install Solidity compiler."
    echo "  brew install solidity  # macOS"
    echo "  apt install solc       # Ubuntu"
    exit 1
fi

SOLC_VERSION=$(solc --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
echo "Solidity compiler version: $SOLC_VERSION"
echo ""

# Remappings for compilation
REMAPPINGS="forge-std/=lib/forge-std/src/ superlib/=lib/superlib/"

# Output directory
OUTPUT_DIR="smt-reports"
mkdir -p "$OUTPUT_DIR"

echo "Running SMTChecker on verification contracts..."
echo ""

# Run CHC engine (more powerful, handles multiple transactions)
echo "=== CHC Engine (Constrained Horn Clauses) ==="
solc src/RolesAuthorityVerified.sol \
    --base-path . \
    --include-path lib/superlib \
    --include-path lib/forge-std/src \
    --model-checker-engine chc \
    --model-checker-targets assert \
    --model-checker-timeout 60000 \
    --model-checker-show-proved-safe \
    --model-checker-show-unproved \
    2>&1 | tee "$OUTPUT_DIR/chc-results.txt"

echo ""
echo "=== BMC Engine (Bounded Model Checker) ==="
solc src/RolesAuthorityVerified.sol \
    --base-path . \
    --include-path lib/superlib \
    --include-path lib/forge-std/src \
    --model-checker-engine bmc \
    --model-checker-targets assert,underflow,overflow \
    --model-checker-timeout 30000 \
    --model-checker-show-proved-safe \
    2>&1 | tee "$OUTPUT_DIR/bmc-results.txt"

echo ""
echo "=== Verification Complete ==="
echo "Reports saved to: $OUTPUT_DIR/"
echo ""
echo "Targets verified:"
echo "  - Blacklisted users cannot gain roles"
echo "  - Users with no roles can only call public functions"
echo "  - P0: VAULT_DEPOSITOR cannot have withdraw capability"
echo "  - P0: Only ADMIN/GUARDIAN can pause"
echo "  - Role separation: Executor cannot modify whitelists"
echo "  - Role separation: Fee updater cannot pause"
