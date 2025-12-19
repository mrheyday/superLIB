# ============================================================================
# SuperLIB Makefile
# ============================================================================

.PHONY: all build test clean fmt lint check coverage snapshot docs deploy help

# Colors for output
CYAN := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
RESET := \033[0m

# Default target
all: clean install build test

# ============================================================================
# Setup
# ============================================================================

install: ## Install dependencies
	@echo "$(CYAN)Installing dependencies...$(RESET)"
	forge install
	@if [ -f package.json ]; then npm install; fi

update: ## Update dependencies
	@echo "$(CYAN)Updating dependencies...$(RESET)"
	forge update

# ============================================================================
# Build
# ============================================================================

build: ## Build contracts
	@echo "$(CYAN)Building contracts...$(RESET)"
	forge build

build-sizes: ## Build and show contract sizes
	@echo "$(CYAN)Building with sizes...$(RESET)"
	forge build --sizes

build-production: ## Build for production (max optimization)
	@echo "$(CYAN)Building for production...$(RESET)"
	FOUNDRY_PROFILE=production forge build

clean: ## Clean build artifacts
	@echo "$(CYAN)Cleaning...$(RESET)"
	forge clean
	rm -rf cache out broadcast

# ============================================================================
# Testing
# ============================================================================

test: ## Run all tests
	@echo "$(CYAN)Running tests...$(RESET)"
	forge test -vvv

test-unit: ## Run unit tests only
	@echo "$(CYAN)Running unit tests...$(RESET)"
	forge test --match-path "test/unit/*" -vvv

test-integration: ## Run integration tests
	@echo "$(CYAN)Running integration tests...$(RESET)"
	forge test --match-path "test/integration/*" -vvv

test-invariant: ## Run invariant/fuzz tests
	@echo "$(CYAN)Running invariant tests...$(RESET)"
	forge test --match-path "test/*Invariant*" -vvvv

test-gas: ## Run tests with gas reporting
	@echo "$(CYAN)Running tests with gas report...$(RESET)"
	forge test --gas-report

test-fork: ## Run fork tests (requires RPC_URL)
	@echo "$(CYAN)Running fork tests...$(RESET)"
	forge test --fork-url $(RPC_URL) -vvv

coverage: ## Generate coverage report
	@echo "$(CYAN)Generating coverage...$(RESET)"
	forge coverage --report lcov
	@echo "$(GREEN)Coverage report: lcov.info$(RESET)"

coverage-html: coverage ## Generate HTML coverage report
	@echo "$(CYAN)Generating HTML coverage...$(RESET)"
	genhtml lcov.info -o coverage --branch-coverage
	@echo "$(GREEN)Open coverage/index.html$(RESET)"

snapshot: ## Update gas snapshot
	@echo "$(CYAN)Updating gas snapshot...$(RESET)"
	forge snapshot

snapshot-check: ## Check gas snapshot for regressions
	@echo "$(CYAN)Checking gas snapshot...$(RESET)"
	forge snapshot --check

# ============================================================================
# Code Quality
# ============================================================================

fmt: ## Format code
	@echo "$(CYAN)Formatting...$(RESET)"
	forge fmt

fmt-check: ## Check formatting
	@echo "$(CYAN)Checking format...$(RESET)"
	forge fmt --check

lint: ## Run linter
	@echo "$(CYAN)Linting...$(RESET)"
	forge lint
	@if command -v solhint > /dev/null; then \
		echo "$(CYAN)Running solhint...$(RESET)"; \
		solhint 'src/**/*.sol' --fix; \
	fi

check: fmt-check lint ## Run all checks
	@echo "$(GREEN)All checks passed!$(RESET)"

# ============================================================================
# Security
# ============================================================================

slither: ## Run Slither static analysis
	@echo "$(CYAN)Running Slither...$(RESET)"
	slither . --filter-paths "lib/|test/|script/" --exclude-dependencies

mythril: ## Run Mythril analysis
	@echo "$(CYAN)Running Mythril...$(RESET)"
	@for file in src/*.sol; do \
		echo "Analyzing $$file..."; \
		myth analyze "$$file" --solc-json mythril.config.json || true; \
	done

security: slither ## Run all security checks
	@echo "$(GREEN)Security analysis complete$(RESET)"

audit-check: ## Quick security pattern check
	@echo "$(CYAN)Checking for dangerous patterns...$(RESET)"
	@echo ""
	@echo "Checking for tx.origin..."
	@grep -rn "tx\.origin" src/ --include="*.sol" || echo "$(GREEN)✓ No tx.origin found$(RESET)"
	@echo ""
	@echo "Checking for selfdestruct..."
	@grep -rn "selfdestruct\|suicide" src/ --include="*.sol" || echo "$(GREEN)✓ No selfdestruct found$(RESET)"
	@echo ""
	@echo "Checking for arbitrary delegatecall..."
	@grep -rn "delegatecall" src/ --include="*.sol" | grep -v "// SAFE:" || echo "$(GREEN)✓ No unsafe delegatecall found$(RESET)"
	@echo ""
	@echo "Checking for unchecked low-level calls..."
	@grep -rn "\.call{" src/ --include="*.sol" -A2 | grep -v "if (" | grep -v "require(" | grep -v "// SAFE:" || echo "$(GREEN)✓ All low-level calls checked$(RESET)"

# ============================================================================
# Documentation
# ============================================================================

docs: ## Generate documentation
	@echo "$(CYAN)Generating documentation...$(RESET)"
	forge doc --build

docs-serve: docs ## Serve documentation locally
	@echo "$(CYAN)Serving docs at http://localhost:3000$(RESET)"
	forge doc --serve --port 3000

# ============================================================================
# Deployment
# ============================================================================

deploy-local: ## Deploy to local Anvil
	@echo "$(CYAN)Deploying to local...$(RESET)"
	forge script script/DeployWithRoles.s.sol --rpc-url http://localhost:8545 --broadcast

deploy-sepolia: ## Deploy to Sepolia testnet
	@echo "$(CYAN)Deploying to Sepolia...$(RESET)"
	forge script script/DeployProduction.s.sol --rpc-url $(SEPOLIA_RPC_URL) --broadcast --verify

deploy-mainnet: ## Deploy to mainnet (dry-run first!)
	@echo "$(YELLOW)⚠️  Mainnet deployment - running dry-run first$(RESET)"
	forge script script/DeployProduction.s.sol --rpc-url $(MAINNET_RPC_URL) -vvvv
	@echo ""
	@read -p "Proceed with broadcast? [y/N] " confirm && [ "$$confirm" = "y" ] && \
		forge script script/DeployProduction.s.sol --rpc-url $(MAINNET_RPC_URL) --broadcast --verify

anvil: ## Start local Anvil node
	@echo "$(CYAN)Starting Anvil...$(RESET)"
	anvil --block-time 1

# ============================================================================
# Utilities
# ============================================================================

abi: ## Export ABIs
	@echo "$(CYAN)Exporting ABIs...$(RESET)"
	@mkdir -p abi
	@for file in out/*.sol/*.json; do \
		name=$$(basename $$(dirname $$file) .sol); \
		if [[ ! "$$name" =~ ^(Test|Script|Mock|I[A-Z]) ]]; then \
			jq '.abi' "$$file" > "abi/$${name}.json" 2>/dev/null && \
			echo "Exported abi/$${name}.json"; \
		fi \
	done

storage: ## Show storage layout
	@echo "$(CYAN)Storage layouts...$(RESET)"
	forge inspect FeeVault storage-layout --pretty
	forge inspect UltimateArbitrageEngine storage-layout --pretty

gas-diff: ## Compare gas with main branch
	@echo "$(CYAN)Comparing gas with main...$(RESET)"
	@git stash
	@forge snapshot --snap .gas-snapshot-main
	@git stash pop
	@forge snapshot --diff .gas-snapshot-main

tree: ## Show contract inheritance tree
	@echo "$(CYAN)Contract tree...$(RESET)"
	forge tree

# ============================================================================
# Help
# ============================================================================

help: ## Show this help
	@echo ""
	@echo "$(CYAN)SuperLIB Development Commands$(RESET)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-18s$(RESET) %s\n", $$1, $$2}'
	@echo ""
