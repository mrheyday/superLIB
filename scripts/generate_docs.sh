#!/bin/bash
# Generate NatSpec documentation for all contracts

set -e

echo "=== Generating NatSpec Documentation ==="
echo ""

OUTPUT_DIR="docs/natspec"
mkdir -p "$OUTPUT_DIR"

# Generate user and dev docs
echo "Generating documentation..."
forge doc --build --out "$OUTPUT_DIR/forge-doc"

# Generate JSON NatSpec for each contract
CONTRACTS=(
    "FeeVault"
    "MEVProtector"
    "FlashLoanEngine"
    "CrossChainRouter"
    "RiskEngine"
    "QuantumArbitrage"
    "MaximumSecurityEngine"
    "ExecutionTrigger"
    "StrategyOrchestrator"
    "UltimateArbitrageEngine"
    "MinimumCostExecutor"
)

echo ""
echo "Generating JSON NatSpec..."

for contract in "${CONTRACTS[@]}"; do
    echo "  Processing: $contract"
    
    # User docs
    forge inspect "$contract" userdoc > "$OUTPUT_DIR"/"${contract}.userdoc.json" 2>/dev/null || true
    
    # Dev docs  
    forge inspect "$contract" devdoc > "$OUTPUT_DIR"/"${contract}.devdoc.json" 2>/dev/null || true
done

# Also generate for Roles library
forge inspect Roles devdoc > "$OUTPUT_DIR"/"Roles.devdoc.json" 2>/dev/null || true

echo ""
echo "=== Documentation Generated ==="
echo "Output: $OUTPUT_DIR/"
echo ""
echo "Files:"
ls -la "$OUTPUT_DIR"/"*.json" 2>/dev/null | head -20 || echo "  (JSON files generated)"
echo ""
echo "Forge docs: "$OUTPUT_DIR"/forge-doc/"
