# Yul Optimizations Guide

Gas optimization techniques using Yul (inline assembly) for the Superlib Arbitrage Protocol.

## When to Use Yul

Use Yul for:
- Hot paths executed frequently (flash loan callbacks, swaps)
- Bitwise operations (role checking)
- Memory operations (calldata parsing, return data handling)
- Avoiding Solidity's safety checks when you've already validated

**Do NOT use Yul for:**
- Complex logic (harder to audit)
- Anything involving external trust assumptions
- Code that benefits from SMTChecker verification

## Role Checking Optimization

### Solidity Version
```solidity
function canCall(address user, address target, bytes4 sig) public view returns (bool) {
    bytes32 roles = getUserRoles[user];
    bytes32 capability = getRolesWithCapability[target][sig];
    return (roles & capability) != bytes32(0) || isCapabilityPublic[target][sig];
}
```

### Yul Optimized Version
```solidity
function canCall(address user, address target, bytes4 sig) public view returns (bool result) {
    assembly {
        // Load user roles from storage
        // slot = keccak256(user, getUserRoles.slot)
        mstore(0x00, user)
        mstore(0x20, 0) // getUserRoles slot
        let rolesSlot := keccak256(0x00, 0x40)
        let roles := sload(rolesSlot)
        
        // Load capability from nested mapping
        // slot = keccak256(sig, keccak256(target, getRolesWithCapability.slot))
        mstore(0x00, target)
        mstore(0x20, 1) // getRolesWithCapability slot
        let innerSlot := keccak256(0x00, 0x40)
        mstore(0x00, sig)
        mstore(0x20, innerSlot)
        let capSlot := keccak256(0x00, 0x40)
        let capability := sload(capSlot)
        
        // Check (roles & capability) != 0
        result := iszero(iszero(and(roles, capability)))
        
        // If not authorized, check public capability
        if iszero(result) {
            mstore(0x00, target)
            mstore(0x20, 2) // isCapabilityPublic slot
            let pubInnerSlot := keccak256(0x00, 0x40)
            mstore(0x00, sig)
            mstore(0x20, pubInnerSlot)
            let pubSlot := keccak256(0x00, 0x40)
            result := sload(pubSlot)
        }
    }
}
```

**Gas savings: ~200-400 gas** (avoids SLOAD redundancy, memory reuse)

## Flash Loan Callback Optimization

### Calldata Parsing in Yul
```solidity
function onFlashLoan(
    address initiator,
    address token,
    uint256 amount,
    uint256 fee,
    bytes calldata data
) external returns (bytes32) {
    // Yul for efficient calldata parsing
    address target;
    bytes4 selector;
    uint256 minProfit;
    
    assembly {
        // data is at offset 164 (4 + 5*32)
        // First 32 bytes of data = target (address)
        target := calldataload(add(data.offset, 0))
        // Mask to address
        target := and(target, 0xffffffffffffffffffffffffffffffffffffffff)
        
        // Next 4 bytes = selector
        selector := calldataload(add(data.offset, 32))
        selector := shr(224, selector) // Right-align bytes4
        
        // Next 32 bytes = minProfit
        minProfit := calldataload(add(data.offset, 36))
    }
    
    // Continue with validated data...
}
```

## Safe Transfer Optimization

Superlib's SafeTransferLib already uses optimized assembly, but here's the pattern:

```solidity
function safeTransfer(address token, address to, uint256 amount) internal {
    assembly {
        // Get free memory pointer
        let freeMemPtr := mload(0x40)
        
        // transfer(address,uint256) selector = 0xa9059cbb
        mstore(freeMemPtr, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
        mstore(add(freeMemPtr, 4), to)
        mstore(add(freeMemPtr, 36), amount)
        
        // Call and check success
        let success := call(gas(), token, 0, freeMemPtr, 68, 0, 32)
        
        // Check return value (handle tokens that return nothing)
        let returned := mload(0)
        if iszero(and(success, or(iszero(returndatasize()), eq(returned, 1)))) {
            // revert with "TRANSFER_FAILED"
            mstore(0, 0x08c379a000000000000000000000000000000000000000000000000000000000)
            mstore(4, 32)
            mstore(36, 15)
            mstore(68, "TRANSFER_FAILED")
            revert(0, 100)
        }
    }
}
```

## Transient Storage (EIP-1153)

For reentrancy guards in Cancun+ (used by `ReentrancyLib`):

```solidity
// Traditional (expensive)
uint256 private _status;
modifier nonReentrant() {
    require(_status != 2);
    _status = 2;
    _;
    _status = 1;
}

// Transient storage (cheap)
modifier nonReentrant() {
    assembly {
        if tload(0) { revert(0, 0) }
        tstore(0, 1)
    }
    _;
    assembly {
        tstore(0, 0)
    }
}
```

**Gas savings: ~2,900 gas** per call (TSTORE = 100 vs SSTORE cold = 20,000)

## Bitwise Role Operations

### Check if user has specific role
```solidity
function hasRole(bytes32 userRoles, uint8 role) internal pure returns (bool) {
    assembly {
        // (userRoles >> role) & 1
        mstore(0, and(shr(role, userRoles), 1))
        return(0, 32)
    }
}
```

### Set role bit
```solidity
function setRoleBit(bytes32 userRoles, uint8 role) internal pure returns (bytes32) {
    assembly {
        // userRoles | (1 << role)
        mstore(0, or(userRoles, shl(role, 1)))
        return(0, 32)
    }
}
```

### Clear role bit
```solidity
function clearRoleBit(bytes32 userRoles, uint8 role) internal pure returns (bytes32) {
    assembly {
        // userRoles & ~(1 << role)
        mstore(0, and(userRoles, not(shl(role, 1))))
        return(0, 32)
    }
}
```

## Memory Layout for Flash Loans

Efficient memory layout for multi-hop arbitrage:

```
Memory Layout:
0x00-0x3f: Scratch space (keccak256, return values)
0x40-0x5f: Free memory pointer
0x60-0x7f: Zero slot
0x80+: Dynamic allocation

Optimized arbitrage data packing:
[0x80] hop_count (1 byte)
[0x81] token_in (20 bytes)  
[0x95] token_out (20 bytes)
[0xa9] amount_in (32 bytes)
[0xc9] min_out (32 bytes)
[0xe9+] hops[] (variable)

Each hop:
[+0]  dex_router (20 bytes)
[+20] pool_fee (3 bytes)
[+23] token_out (20 bytes)
```

## Compiler Flags

Enable IR-based codegen for better Yul optimization:

```toml
# foundry.toml
[profile.default]
via_ir = true
optimizer = true
optimizer_runs = 200

[profile.default.optimizer_details.yul_details]
stack_allocation = true
optimizer_steps = "dhfoDgvulfnTUtnIf"
```

## Verification Warning

⚠️ **Yul code cannot be verified by SMTChecker**

The SMTChecker abstracts assembly blocks, which may cause:
- False positives (SMT assumes worst case)
- Missed bugs (SMT can't analyze assembly logic)

**Mitigation:**
1. Keep Yul blocks small and well-documented
2. Write extensive fuzz tests for Yul functions
3. Use Echidna/Foundry invariant tests
4. Manual audit of all assembly code

## Reference: EVM Opcodes Used

| Opcode | Gas | Description |
|--------|-----|-------------|
| `sload` | 2100 cold / 100 warm | Load from storage |
| `sstore` | 20000 cold / 2900 warm | Store to storage |
| `tload` | 100 | Load from transient storage |
| `tstore` | 100 | Store to transient storage |
| `mload` | 3 | Load from memory |
| `mstore` | 3 | Store to memory |
| `keccak256` | 30 + 6/word | Hash memory |
| `calldataload` | 3 | Load from calldata |
| `and/or/xor` | 3 | Bitwise ops |
| `shl/shr` | 3 | Shift ops |

## Further Reading

- [Yul Specification](https://docs.soliditylang.org/en/latest/yul.html)
- [EVM Opcodes](https://www.evm.codes/)
- [Solmate Optimizations](https://github.com/transmissions11/solmate)
