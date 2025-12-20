#!/usr/bin/env bash
set -euo pipefail

echo "Creating Superlib directory structure..."

# Base directory
BASE="src"

# Define directories
declare -a DIRS=(
  "$BASE/core"
  "$BASE/access"
  "$BASE/security"
  "$BASE/transfer"
  "$BASE/utils"
  "$BASE/deploy"
)

# Create directories
for dir in "${DIRS[@]}"; do
  mkdir -p "$dir"
done

echo "Directories created."

# Create core token standards files
cat > "$BASE/core/ERC6909Strict.sol" << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ERC6909Strict
/// @notice Core ERC6909 minimal multi-token implementation
contract ERC6909Strict {
    // Implementation here...
}
EOF

cat > "$BASE/core/ERC6909Batch.sol" << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ERC6909Batch
/// @notice Batch transfers for ERC6909
contract ERC6909Batch {
    // Implementation here...
}
EOF

cat > "$BASE/core/ERC6909Permit.sol" << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ERC6909Permit
/// @notice ERC6909 signature-based approvals
contract ERC6909Permit {
    // Implementation here...
}
EOF

cat > "$BASE/core/ERC6909Metadata.sol" << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ERC6909Metadata
/// @notice Metadata interface for ERC6909 tokens
contract ERC6909Metadata {
    // Implementation here...
}
EOF

cat > "$BASE/core/IERC6909URIResolver.sol" << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IERC6909URIResolver
/// @notice External resolver interface
interface IERC6909URIResolver {
    function resolveURI(uint256 id) external view returns (string memory);
}
EOF

# Access control
cat > "$BASE/access/AccessRolesLite.sol" << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title AccessRolesLite
/// @notice Minimal role assignment
contract AccessRolesLite {
    // Implementation here...
}
EOF

# Security
cat > "$BASE/security/EIP712Strict.sol" << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title EIP712Strict
/// @notice EIP712 domain and helpers
contract EIP712Strict {
    // Implementation here...
}
EOF

cat > "$BASE/security/ECDSALib.sol" << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ECDSALib
/// @notice ECDSA helpers
library ECDSALib {
    // Implementation here...
}
EOF

cat > "$BASE/security/Permit2Helpers.sol" << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Permit2Helpers
/// @notice Helpers for Permit2 style flows
library Permit2Helpers {
    // Implementation here...
}
EOF

cat > "$BASE/security/ExecutionGuardLib.sol" << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ExecutionGuardLib
/// @notice Anti-replay / per-call nonce guard
library ExecutionGuardLib {
    // Implementation here...
}
EOF

cat > "$BASE/security/ReentrancyLib.sol" << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ReentrancyLib
/// @notice Reentrancy guard utilities
library ReentrancyLib {
    // Implementation here...
}
EOF

# Transfer
cat > "$BASE/transfer/SafeTransferLib.sol" << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title SafeTransferLib
/// @notice Safe ETH/ERC20/ERC721 transport helpers
library SafeTransferLib {
    // Implementation here...
}
EOF

# Utils
cat > "$BASE/utils/BytesLib.sol" << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title BytesLib
/// @notice Byte manipulation helpers
library BytesLib {
    // Implementation here...
}
EOF

cat > "$BASE/utils/MathLib.sol" << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title MathLib
/// @notice Numeric helper functions
library MathLib {
    // Implementation here...
}
EOF

cat > "$BASE/utils/LibBit.sol" << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title LibBit
/// @notice Bitfield manipulation helpers
library LibBit {
    // Implementation here...
}
EOF

cat > "$BASE/utils/SignedWadLib.sol" << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title SignedWadLib
/// @notice Signed fixed-point arithmetic
library SignedWadLib {
    // Implementation here...
}
EOF

cat > "$BASE/utils/OracleSafetyLib.sol" << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title OracleSafetyLib
/// @notice Oracle freshness & bounds checks
library OracleSafetyLib {
    // Implementation here...
}
EOF

# Deploy
cat > "$BASE/deploy/Create3Deployer.sol" << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Create3Deployer
/// @notice Deterministic deployment helper
contract Create3Deployer {
    // Implementation here...
}
EOF

# Superlib aggregator
cat > "$BASE/Superlib.sol" << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Superlib
/// @notice Re-exports all core Superlib modules

// Core
import "./core/ERC6909Strict.sol";
import "./core/ERC6909Batch.sol";
import "./core/ERC6909Permit.sol";
import "./core/ERC6909Metadata.sol";
import "./core/IERC6909URIResolver.sol";

// Access
import "./access/AccessRolesLite.sol";

// Security
import "./security/EIP712Strict.sol";
import "./security/ECDSALib.sol";
import "./security/Permit2Helpers.sol";
import "./security/ExecutionGuardLib.sol";
import "./security/ReentrancyLib.sol";

// Transfer
import "./transfer/SafeTransferLib.sol";

// Utils
import "./utils/BytesLib.sol";
import "./utils/MathLib.sol";
import "./utils/LibBit.sol";
import "./utils/SignedWadLib.sol";
import "./utils/OracleSafetyLib.sol";

// Deploy
import "./deploy/Create3Deployer.sol";
EOF

echo "Structure created successfully!"
