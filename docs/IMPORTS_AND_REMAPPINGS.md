# Import Path Resolution Guide

How the Superlib Arbitrage Protocol organizes imports and remappings for reproducible builds.

## Project Structure

```
superlib_protocol/
├── src/                    # Protocol contracts
│   ├── FeeVault.sol
│   ├── roles/
│   │   └── Roles.sol
│   └── utils/
│       └── YulHelpers.sol
├── lib/                    # Dependencies
│   ├── forge-std/          # Foundry testing
│   │   └── src/
│   └── superlib/           # Solmate-style libs
│       ├── auth/
│       ├── core/
│       ├── security/
│       ├── transfer/
│       └── utils/
└── test/                   # Tests
```

## Remappings

Defined in `foundry.toml` and `remappings.txt`:

```toml
# foundry.toml
remappings = [
    "forge-std/=lib/forge-std/src/",
    "superlib/=lib/superlib/",
]
```

```
# remappings.txt (alternative)
forge-std/=lib/forge-std/src/
superlib/=lib/superlib/
```

## Import Patterns

### Direct Imports (Recommended)

```solidity
// From superlib
import {RolesAuthority} from "superlib/auth/RolesAuthority.sol";
import {ERC4626} from "superlib/core/ERC4626.sol";
import {SafeTransferLib} from "superlib/transfer/SafeTransferLib.sol";

// From forge-std
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

// From project src
import {Roles} from "./roles/Roles.sol";
import {FeeVault} from "../FeeVault.sol";
```

### Relative Imports

Only use within the same directory tree:

```solidity
// src/FeeVault.sol
import {Roles} from "./roles/Roles.sol";      // ✅ Same tree

// src/engines/FlashLoanEngine.sol
import {Roles} from "../roles/Roles.sol";     // ✅ Parent tree
import {FeeVault} from "../FeeVault.sol";     // ✅ Sibling

// ❌ Don't use relative for external libs
import {Test} from "../../lib/forge-std/src/Test.sol";  // ❌ Bad
import {Test} from "forge-std/Test.sol";                // ✅ Good
```

## How Remappings Work

```
Import Path                          Source Unit Name
───────────────────────────────────────────────────────
"superlib/auth/RolesAuthority.sol"   lib/superlib/auth/RolesAuthority.sol
"forge-std/Test.sol"                 lib/forge-std/src/Test.sol
"./roles/Roles.sol"                  src/roles/Roles.sol (from src/)
```

### Remapping Resolution Order

1. Check if import matches any remapping prefix
2. Apply longest matching prefix
3. If no match, use import path as-is
4. Pass to filesystem loader

## Adding New Dependencies

### Via Forge

```bash
# Add OpenZeppelin
forge install OpenZeppelin/openzeppelin-contracts

# Add specific version
forge install transmissions11/solmate@v6

# Add from arbitrary git
forge install https://github.com/user/repo
```

### Update Remappings

```bash
# Regenerate remappings
forge remappings > remappings.txt

# Or manually add to foundry.toml
remappings = [
    "forge-std/=lib/forge-std/src/",
    "superlib/=lib/superlib/",
    "@openzeppelin/=lib/openzeppelin-contracts/",  # New
]
```

## Common Import Errors

### Error: Source not found

```
Error: Source "superlib/auth/Auth.sol" not found
```

**Fix:** Check remappings exist and paths are correct:

```bash
# Verify remapping
forge remappings | grep superlib

# Check file exists
ls lib/superlib/auth/Auth.sol
```

### Error: Relative import outside allowed directories

```
Error: File outside of allowed directories
```

**Fix:** Use remapped imports instead of relative paths to external libs.

### Error: Different source unit names for same file

This can happen with inconsistent paths. Normalize imports:

```solidity
// ❌ Inconsistent
import "superlib/auth/Auth.sol";
import "superlib/auth/../auth/Auth.sol";

// ✅ Consistent
import "superlib/auth/Auth.sol";
import "superlib/auth/Auth.sol";
```

## Reproducible Builds

### Metadata and Bytecode

Remapping targets are stored in contract metadata. To ensure reproducible bytecode:

1. **Use consistent remappings** across all build environments
2. **Avoid absolute paths** in remapping targets
3. **Pin dependency versions** in `lib/` via git submodules

### Example Reproducible Setup

```bash
# Clone with submodules
git clone --recursive https://github.com/example/superlib-protocol

# Or init submodules after clone
git submodule update --init --recursive

# Verify exact dependency versions
cat lib/superlib/.git/HEAD
cat lib/forge-std/.git/HEAD
```

## Multi-Version Dependencies

If different parts of your project need different versions:

```toml
# foundry.toml - Context-specific remappings
remappings = [
    # Default: latest superlib
    "superlib/=lib/superlib/",
    
    # Legacy module uses old version
    "legacy-contracts/:superlib/=lib/superlib-v1/",
]
```

```solidity
// src/new/Contract.sol
import {Auth} from "superlib/auth/Auth.sol";  // Uses lib/superlib/

// src/legacy-contracts/OldContract.sol  
import {Auth} from "superlib/auth/Auth.sol";  // Uses lib/superlib-v1/
```

## NPM-Style Imports

For compatibility with npm package structure:

```toml
# foundry.toml
remappings = [
    "@openzeppelin/contracts/=node_modules/@openzeppelin/contracts/",
    "@uniswap/v3-core/=node_modules/@uniswap/v3-core/",
]
```

```solidity
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
```

## Verification Considerations

When verifying on Etherscan:

1. **Export remappings**: `forge remappings > remappings.txt`
2. **Flatten if needed**: `forge flatten src/FeeVault.sol`
3. **Use Standard JSON**: More reliable than flattening

```bash
# Generate Standard JSON input
forge verify-contract \
    --chain mainnet \
    --compiler-version v0.8.28 \
    --constructor-args $(cast abi-encode "constructor(address)" 0x...) \
    0xCONTRACT_ADDRESS \
    src/FeeVault.sol:FeeVault
```

## IDE Configuration

### VSCode + Solidity Extension

`.vscode/settings.json`:

```json
{
    "solidity.packageDefaultDependenciesDirectory": "lib",
    "solidity.remappings": [
        "forge-std/=lib/forge-std/src/",
        "superlib/=lib/superlib/"
    ]
}
```

### Remixd

```bash
remixd -s . --remix-ide https://remix.ethereum.org
```

Then use remappings in Remix settings.

## Summary

| Import Type | Example | Use Case |
|-------------|---------|----------|
| Remapped | `import "superlib/auth/Auth.sol"` | External dependencies |
| Relative `./` | `import "./Roles.sol"` | Same directory |
| Relative `../` | `import "../FeeVault.sol"` | Parent directory |
| Absolute | `import "/project/src/Contract.sol"` | Avoid (not portable) |

**Best Practices:**
1. Always use remapped imports for external libs
2. Use relative imports only within `src/` tree
3. Pin dependency versions via git submodules
4. Keep remappings in `foundry.toml` (single source of truth)
5. Regenerate `remappings.txt` for IDE compatibility
