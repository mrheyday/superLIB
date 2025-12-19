#!/bin/bash
# Mythril Analysis Script
# Run comprehensive symbolic execution on all protocol contracts

set -e

CONTRACTS=(
    "src/FeeVault.sol:FeeVault"
    "src/MEVProtector.sol:MEVProtector"
    "src/FlashLoanEngine.sol:FlashLoanEngine"
    "src/CrossChainRouter.sol:CrossChainRouter"
    "src/RiskEngine.sol:RiskEngine"
    "src/QuantumArbitrage.sol:QuantumArbitrage"
    "src/MaximumSecurityEngine.sol:MaximumSecurityEngine"
    "src/ExecutionTrigger.sol:ExecutionTrigger"
    "src/StrategyOrchestrator.sol:StrategyOrchestrator"
    "src/UltimateArbitrageEngine.sol:UltimateArbitrageEngine"
    "lib/superlib/auth/RolesAuthority.sol:RolesAuthority"
)

OUTPUT_DIR="mythril/reports"
mkdir -p "$OUTPUT_DIR"

echo "=== Mythril Security Analysis ==="
echo "Analyzing ${#CONTRACTS[@]} contracts..."
echo ""

# Compile first
echo "Compiling contracts..."
forge build --force

for contract in "${CONTRACTS[@]}"; do
    IFS=':' read -r file name <<< "$contract"
    echo ""
    echo "Analyzing: $name ($file)"
    echo "----------------------------------------"
    
    # Run Mythril analysis
    myth analyze "$file" \
        --solc-json mythril.config.json \
        --solv 0.8.28 \
        --execution-timeout 300 \
        --max-depth 50 \
        --strategy bfs \
        -o jsonv2 \
        > "$OUTPUT_DIR/${name}.json" 2>&1 || true
    
    # Also generate text report
    myth analyze "$file" \
        --solc-json mythril.config.json \
        --solv 0.8.28 \
        --execution-timeout 300 \
        --max-depth 50 \
        --strategy bfs \
        -o text \
        > "$OUTPUT_DIR/${name}.txt" 2>&1 || true
    
    # Check for critical issues
    if grep -q "SWC-10[1-7]" "$OUTPUT_DIR/${name}.txt" 2>/dev/null; then
        echo "⚠️  CRITICAL ISSUES FOUND in $name"
    elif grep -q "SWC-" "$OUTPUT_DIR/${name}.txt" 2>/dev/null; then
        echo "⚡ Issues found in $name (review report)"
    else
        echo "✅ No issues found in $name"
    fi
done

echo ""
echo "=== Analysis Complete ==="
echo "Reports saved to: $OUTPUT_DIR/"
echo ""
echo "Critical SWC IDs to watch:"
echo "  SWC-101: Integer Overflow/Underflow"
echo "  SWC-104: Unchecked Call Return Value"
echo "  SWC-105: Unprotected Ether Withdrawal"
echo "  SWC-106: Unprotected SELFDESTRUCT"
echo "  SWC-107: Reentrancy"
echo "  SWC-115: Authorization through tx.origin"
echo "  SWC-116: Timestamp Dependence"
