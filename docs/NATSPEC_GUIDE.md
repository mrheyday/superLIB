# NatSpec Documentation Guide

Guidelines for documenting the Superlib Arbitrage Protocol contracts.

## Required Tags

All public/external functions MUST include:

```solidity
/// @notice Brief description for end users
/// @dev Technical details for developers
/// @param paramName Description of parameter
/// @return Description of return value
function example(uint256 paramName) external returns (uint256) { ... }
```

## Contract-Level Documentation

Every contract MUST include:

```solidity
/// @title ContractName
/// @author Team Name
/// @notice What this contract does (user-facing)
/// @dev Implementation details, inheritance, security notes
/// @custom:security-contact security@example.com
/// @custom:audit-status Audit status and findings
contract ContractName { ... }
```

## Custom Tags

We use these custom tags consistently:

| Tag | Purpose |
|-----|---------|
| `@custom:security-contact` | Security disclosure email |
| `@custom:audit-status` | Audit completion status |
| `@custom:audit` | Specific audit finding reference |
| `@custom:invariant` | Mathematical invariant this enforces |
| `@custom:access` | Role(s) required to call |

## Role Documentation Pattern

```solidity
/// @notice Withdraw assets from vault
/// @dev Only ADMIN role can call - P0 audit fix separated from VAULT_DEPOSITOR
/// @custom:access Requires ADMIN role
/// @custom:audit P0 fix - Withdrawal restricted from AI agent
/// @param assets Amount of underlying to withdraw
/// @param receiver Address to receive assets
/// @param owner Address that owns the shares
/// @return shares Amount of shares burned
function withdraw(
    uint256 assets,
    address receiver,
    address owner
) external requiresAuth returns (uint256 shares) { ... }
```

## Event Documentation

```solidity
/// @notice Emitted when deposit fee is updated
/// @param oldFee Previous fee value (basis points)
/// @param newFee New fee value (basis points)
event DepositFeeUpdated(uint256 oldFee, uint256 newFee);
```

## Error Documentation

```solidity
/// @notice Thrown when fee exceeds maximum allowed
/// @param fee The fee that was attempted
/// @param maxFee The maximum allowed fee
error FeeExceedsMax(uint256 fee, uint256 maxFee);
```

## State Variable Documentation

```solidity
/// @notice Maximum fee in basis points (10% = 1000)
/// @dev Used to cap deposit, withdraw, and performance fees
uint256 public constant MAX_FEE = 1000;

/// @notice Current deposit fee in basis points
/// @dev Updated via setDepositFee(), requires FEE_UPDATER role
uint256 public depositFee;
```

## Inheritance Documentation

Use `@inheritdoc` for overridden functions:

```solidity
/// @inheritdoc ERC4626
/// @dev Adds fee deduction before standard ERC4626 deposit
function deposit(uint256 assets, address receiver) 
    public 
    override 
    returns (uint256) 
{ ... }
```

## Generating Documentation

```bash
# Generate all docs
npm run docs:natspec

# Serve interactive docs
npm run docs:serve

# Generate JSON only
forge inspect FeeVault userdoc
forge inspect FeeVault devdoc
```

## Output Format

User documentation (userdoc):
```json
{
  "version": 1,
  "kind": "user",
  "methods": {
    "deposit(uint256,address)": {
      "notice": "Deposit assets into vault and receive shares"
    }
  }
}
```

Developer documentation (devdoc):
```json
{
  "version": 1,
  "kind": "dev",
  "methods": {
    "deposit(uint256,address)": {
      "details": "Applies deposit fee, requires VAULT_DEPOSITOR role",
      "params": {
        "assets": "Amount of underlying to deposit",
        "receiver": "Address to receive shares"
      },
      "returns": {
        "_0": "shares Amount of shares minted"
      }
    }
  }
}
```

## Checklist

Before submitting a PR, verify:

- [ ] All public/external functions have `@notice`
- [ ] All functions have `@param` for each parameter
- [ ] All functions have `@return` for each return value
- [ ] All state-changing functions have `@custom:access`
- [ ] All audit-related changes have `@custom:audit`
- [ ] Contract has `@title`, `@author`, `@notice`, `@dev`
- [ ] All events have `@notice` and `@param`
- [ ] All errors have `@notice` and `@param`
