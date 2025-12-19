# Makefile for DeFi Arbitrage Protocol Tests

.PHONY: all test test-gas test-fuzz test-invariant coverage deploy clean

# Default target
all: test

# Install dependencies
install:
	forge install OpenZeppelin/openzeppelin-contracts --no-commit
	forge install foundry-rs/forge-std --no-commit

# Compile contracts
build:
	forge build

# Run all tests
test:
	forge test -vvv

# Run tests with gas reporting
test-gas:
	forge test --gas-report

# Run fuzz tests with extended iterations
test-fuzz:
	FOUNDRY_FUZZ_RUNS=1000 forge test --match-path "test/*.t.sol"

# Run invariant tests
test-invariant:
	forge test --match-path test/Invariant.t.sol -vvv

# Run attack vector tests
test-attacks:
	forge test --match-path test/AttackVectors.t.sol -vvv

# Run specific contract tests
test-vault:
	forge test --match-path test/FeeVault.t.sol -vvv

test-mev:
	forge test --match-path test/MEVProtector.t.sol -vvv

test-security:
	forge test --match-path test/MaximumSecurityEngine.t.sol -vvv

test-flash:
	forge test --match-path test/FlashLoanEngine.t.sol -vvv

test-cross:
	forge test --match-path test/CrossChainRouter.t.sol -vvv

# Generate coverage report
coverage:
	forge coverage --report lcov
	genhtml lcov.info -o coverage/

# Format code
fmt:
	forge fmt

# Lint code
lint:
	forge fmt --check

# Deploy to local anvil
deploy-local:
	anvil &
	sleep 2
	forge script script/DeployTestnet.s.sol:DeployTestnet \
		--rpc-url http://localhost:8545 \
		--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
		--broadcast

# Deploy to testnet (requires PRIVATE_KEY and RPC_URL env vars)
deploy-testnet:
	forge script script/DeployTestnet.s.sol:DeployTestnet \
		--rpc-url $(RPC_URL) \
		--broadcast \
		--verify

# Deploy to mainnet (requires PRIVATE_KEY, RPC_URL, ADMIN_ADDRESS, FEE_RECIPIENT env vars)
deploy-mainnet:
	forge script script/DeployCore.s.sol:DeployCore \
		--rpc-url $(RPC_URL) \
		--broadcast \
		--verify \
		--slow

# Generate documentation
docs:
	forge doc

# Clean build artifacts
clean:
	forge clean
	rm -rf coverage/
	rm -f lcov.info

# Quick smoke test
smoke:
	forge test --match-test "test_constructor" -vv

# Security-focused test suite
security-audit:
	@echo "Running security-focused tests..."
	@echo "\n=== Attack Vector Tests ===" 
	forge test --match-path test/AttackVectors.t.sol -vvv
	@echo "\n=== Invariant Tests ==="
	forge test --match-path test/Invariant.t.sol -vvv
	@echo "\n=== Access Control Tests ==="
	forge test --match-test "accessControl\|unauthorized\|onlyOwner" -vvv
	@echo "\n=== Security audit complete ==="

# Check for common vulnerabilities using slither (if installed)
slither:
	slither . --config-file slither.config.json

# Help
help:
	@echo "DeFi Arbitrage Protocol - Test Commands"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  install        - Install dependencies"
	@echo "  build          - Compile contracts"
	@echo "  test           - Run all tests"
	@echo "  test-gas       - Run tests with gas reporting"
	@echo "  test-fuzz      - Run fuzz tests (1000 iterations)"
	@echo "  test-invariant - Run invariant tests"
	@echo "  test-attacks   - Run attack vector tests"
	@echo "  test-vault     - Run FeeVault tests"
	@echo "  test-mev       - Run MEVProtector tests"
	@echo "  test-security  - Run MaxSecurityEngine tests"
	@echo "  coverage       - Generate coverage report"
	@echo "  security-audit - Run full security test suite"
	@echo "  deploy-local   - Deploy to local anvil"
	@echo "  deploy-testnet - Deploy to testnet"
	@echo "  deploy-mainnet - Deploy to mainnet"
	@echo "  clean          - Clean build artifacts"
	@echo "  help           - Show this help message"
