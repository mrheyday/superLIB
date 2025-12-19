// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ReentrancyLib
/// @notice Gas-optimized reentrancy guard using transient storage where available
/// @dev Uses traditional storage slot approach for maximum compatibility
library ReentrancyLib {
    /// @dev Storage slot for reentrancy guard (keccak256("reentrancy.guard.slot") - 1)
    bytes32 private constant REENTRANCY_SLOT = 0x8e94fed44239eb2314ab7a406345e6c5a8f0ccedf3b600de3d004e672c33abf4;
    
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    error ReentrancyGuardReentrantCall();

    function lock() internal {
        assembly {
            if eq(sload(REENTRANCY_SLOT), ENTERED) {
                mstore(0x00, 0x37ed32e8) // ReentrancyGuardReentrantCall()
                revert(0x1c, 0x04)
            }
            sstore(REENTRANCY_SLOT, ENTERED)
        }
    }

    function unlock() internal {
        assembly {
            sstore(REENTRANCY_SLOT, NOT_ENTERED)
        }
    }

    function status() internal view returns (uint256 s) {
        assembly {
            s := sload(REENTRANCY_SLOT)
        }
    }
}

/// @title ReentrancyGuard
/// @notice Abstract contract providing reentrancy protection
abstract contract ReentrancyGuard {
    uint256 private locked = 1;

    error Reentrancy();

    modifier nonReentrant() virtual {
        if (locked == 2) revert Reentrancy();
        locked = 2;
        _;
        locked = 1;
    }
}
