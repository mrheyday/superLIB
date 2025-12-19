# Contributing Guide

Thank you for your interest in contributing to the DeFi Arbitrage Protocol. This guide explains how to participate in development effectively and safely.

## Security First

Security is paramount in DeFi development. Before contributing any code, please read the security audit report in `docs/SECURITY_AUDIT.md` to understand the vulnerabilities that have been addressed and the patterns used to mitigate them.

### Responsible Disclosure

If you discover a security vulnerability, do not open a public issue. Instead, report it privately to the security team. Include a detailed description of the vulnerability, steps to reproduce, potential impact assessment, and suggested remediation if available. You will receive acknowledgment within 48 hours and a detailed response within 7 days.

## Development Setup

Fork the repository and clone your fork locally. Install Foundry if you haven't already using the command `curl -L https://foundry.paradigm.xyz | bash` followed by `foundryup`. Install project dependencies by running `forge install` in the project directory. Verify your setup by running `forge build` and `forge test`.

## Code Standards

### Solidity Style

Follow the official Solidity style guide. Use explicit visibility modifiers on all functions and state variables. Prefer custom errors over require statements with string messages. Use NatSpec comments for all public and external functions. Keep functions focused and under 50 lines where practical.

### Security Patterns

All external calls must validate targets against whitelists. Never use `tx.origin` for authentication. Apply the checks-effects-interactions pattern to prevent reentrancy. Use SafeERC20 for token transfers. Validate all numeric inputs have sensible bounds.

### Naming Conventions

Contract names use PascalCase. Function names use camelCase. Constants use SCREAMING_SNAKE_CASE. Internal and private functions are prefixed with underscore. Events are named as past-tense actions such as `DepositCompleted`.

## Testing Requirements

All contributions must include comprehensive tests. Write unit tests for individual functions covering both success and failure cases. Write integration tests for multi-contract interactions. Include fuzz tests for functions accepting numeric parameters. Update existing tests if your changes affect their assumptions.

### Running Tests

Execute the full test suite with `forge test`. Run tests with verbose output using `forge test -vvv`. Run a specific test file with `forge test --match-path test/YourTest.t.sol`. Run extended fuzz testing with `FOUNDRY_FUZZ_RUNS=1000 forge test`.

### Coverage

Generate a coverage report with `forge coverage`. New code should maintain or improve the overall coverage percentage. Critical paths must have 100% coverage.

## Pull Request Process

Create a feature branch from `main` with a descriptive name. Make your changes in small, logical commits with clear messages. Ensure all tests pass locally before pushing. Open a pull request against `main` with a clear description of changes.

### PR Description Template

Your pull request description should include the following sections: a summary of what the PR does and why it's needed, any security considerations relevant to the changes, a testing section describing what tests were added or modified, and a breaking changes section if applicable.

### Review Process

All PRs require at least two approvals from maintainers. Security-sensitive changes require review from a security team member. Address all review comments before merging. Squash commits when merging to maintain clean history.

## Documentation

Update documentation when you change public interfaces. Document new features in the appropriate docs file. Keep code comments current with implementation. Add NatSpec comments to all new public functions.

## Getting Help

If you have questions about contributing, open a discussion issue with your question. For real-time discussion, join the development community channels. Review existing issues and PRs for context on ongoing work.
