// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title AccessListHelper
/// @notice EIP-2930 Access List generation helper for MEV optimization
/// @dev Pre-computes storage slots for DEX interactions to reduce cold access costs
/// @custom:eip EIP-2930 - Optional Access Lists
/// @custom:gas Savings: 2,400 gas per address, 1,900 gas per storage slot
library AccessListHelper {
    // ============================================
    // STORAGE SLOT CONSTANTS
    // ============================================

    /// @dev Uniswap V2 Pair storage slots
    /// reserve0, reserve1, blockTimestampLast packed in slot 8
    uint256 internal constant UNIV2_RESERVES_SLOT = 8;

    /// @dev ERC20 balanceOf mapping is typically slot 0 or 1
    uint256 internal constant ERC20_BALANCE_SLOT_0 = 0;
    uint256 internal constant ERC20_BALANCE_SLOT_1 = 1;

    /// @dev ERC20 allowance mapping is typically slot 1 or 2
    uint256 internal constant ERC20_ALLOWANCE_SLOT_1 = 1;
    uint256 internal constant ERC20_ALLOWANCE_SLOT_2 = 2;

    // ============================================
    // ACCESS LIST GENERATION
    // ============================================

    /// @notice Generate storage slot for ERC20 balance of an address
    /// @dev balanceOf[address] = keccak256(abi.encode(address, slot))
    /// @param holder Address holding the tokens
    /// @param mappingSlot The storage slot of the balanceOf mapping (usually 0 or 1)
    /// @return slot The computed storage slot for the balance
    function getBalanceSlot(
        address,
        /* token */
        address holder,
        uint256 mappingSlot
    )
        internal
        pure
        returns (bytes32 slot)
    {
        slot = keccak256(abi.encode(holder, mappingSlot));
    }

    /// @notice Generate storage slot for ERC20 allowance
    /// @dev allowance[owner][spender] = keccak256(abi.encode(spender, keccak256(abi.encode(owner,
    /// slot)))) @param owner Token owner address
    /// @param spender Spender address (usually the router)
    /// @param mappingSlot The storage slot of the allowance mapping (usually 1 or 2)
    /// @return slot The computed storage slot for the allowance
    function getAllowanceSlot(
        address owner,
        address spender,
        uint256 mappingSlot
    )
        internal
        pure
        returns (bytes32 slot)
    {
        bytes32 innerSlot = keccak256(abi.encode(owner, mappingSlot));
        slot = keccak256(abi.encode(spender, innerSlot));
    }

    /// @notice Get Uniswap V2 pair reserves slot
    /// @return The storage slot containing reserves (always 8)
    function getUniV2ReservesSlot() internal pure returns (bytes32) {
        return bytes32(UNIV2_RESERVES_SLOT);
    }

    // ============================================
    // DEX-SPECIFIC HELPERS
    // ============================================

    /// @notice Generate access list hints for Uniswap V2 swap
    /// @param pair The Uniswap V2 pair address
    /// @param tokenIn Input token address
    /// @param tokenOut Output token address
    /// @param trader The address executing the swap
    /// @param router The router address for approvals
    /// @return addresses Array of addresses to pre-warm
    /// @return slots Array of storage slots per address
    function getUniV2SwapAccessList(
        address pair,
        address tokenIn,
        address tokenOut,
        address trader,
        address router
    )
        internal
        pure
        returns (address[] memory addresses, bytes32[][] memory slots)
    {
        addresses = new address[](3);
        slots = new bytes32[][](3);

        // 1. Pair contract - reserves slot
        addresses[0] = pair;
        slots[0] = new bytes32[](1);
        slots[0][0] = getUniV2ReservesSlot();

        // 2. Input token - balance and allowance
        addresses[1] = tokenIn;
        slots[1] = new bytes32[](3);
        slots[1][0] = getBalanceSlot(tokenIn, trader, ERC20_BALANCE_SLOT_0);
        slots[1][1] = getBalanceSlot(tokenIn, pair, ERC20_BALANCE_SLOT_0);
        slots[1][2] = getAllowanceSlot(trader, router, ERC20_ALLOWANCE_SLOT_1);

        // 3. Output token - balance
        addresses[2] = tokenOut;
        slots[2] = new bytes32[](2);
        slots[2][0] = getBalanceSlot(tokenOut, pair, ERC20_BALANCE_SLOT_0);
        slots[2][1] = getBalanceSlot(tokenOut, trader, ERC20_BALANCE_SLOT_0);
    }

    /// @notice Generate access list hints for Uniswap V3 swap
    /// @param pool The Uniswap V3 pool address
    /// @param tokenIn Input token address
    /// @param tokenOut Output token address
    /// @param trader The address executing the swap
    /// @return addresses Array of addresses to pre-warm
    /// @return slots Array of storage slots per address
    function getUniV3SwapAccessList(
        address pool,
        address tokenIn,
        address tokenOut,
        address trader
    )
        internal
        pure
        returns (address[] memory addresses, bytes32[][] memory slots)
    {
        addresses = new address[](3);
        slots = new bytes32[][](3);

        // 1. Pool contract - slot0 (contains sqrtPriceX96, tick, etc.)
        addresses[0] = pool;
        slots[0] = new bytes32[](2);
        slots[0][0] = bytes32(uint256(0)); // slot0
        slots[0][1] = bytes32(uint256(4)); // liquidity slot

        // 2. Input token - balance
        addresses[1] = tokenIn;
        slots[1] = new bytes32[](2);
        slots[1][0] = getBalanceSlot(tokenIn, trader, ERC20_BALANCE_SLOT_0);
        slots[1][1] = getBalanceSlot(tokenIn, pool, ERC20_BALANCE_SLOT_0);

        // 3. Output token - balance
        addresses[2] = tokenOut;
        slots[2] = new bytes32[](2);
        slots[2][0] = getBalanceSlot(tokenOut, pool, ERC20_BALANCE_SLOT_0);
        slots[2][1] = getBalanceSlot(tokenOut, trader, ERC20_BALANCE_SLOT_0);
    }

    /// @notice Generate access list for flash loan
    /// @param lender Flash loan provider (Aave, Balancer, etc.)
    /// @param token Token being borrowed
    /// @param borrower Address receiving the loan
    /// @return addresses Array of addresses to pre-warm
    /// @return slots Array of storage slots per address
    function getFlashLoanAccessList(
        address lender,
        address token,
        address borrower
    )
        internal
        pure
        returns (address[] memory addresses, bytes32[][] memory slots)
    {
        addresses = new address[](2);
        slots = new bytes32[][](2);

        // 1. Lender contract
        addresses[0] = lender;
        slots[0] = new bytes32[](0); // Access list just warms the address

        // 2. Token - balances for lender and borrower
        addresses[1] = token;
        slots[1] = new bytes32[](2);
        slots[1][0] = getBalanceSlot(token, lender, ERC20_BALANCE_SLOT_0);
        slots[1][1] = getBalanceSlot(token, borrower, ERC20_BALANCE_SLOT_0);
    }

    // ============================================
    // GAS ESTIMATION
    // ============================================

    /// @notice Estimate gas savings from using access lists
    /// @param numAddresses Number of addresses in access list
    /// @param numStorageKeys Total number of storage keys
    /// @return coldAccessCost Gas without access list (cold access)
    /// @return warmAccessCost Gas with access list (warm access + upfront cost)
    /// @return savings Net gas savings (can be negative for small lists)
    function estimateGasSavings(
        uint256 numAddresses,
        uint256 numStorageKeys
    )
        internal
        pure
        returns (uint256 coldAccessCost, uint256 warmAccessCost, int256 savings)
    {
        // Cold access costs
        uint256 coldAddressCost = numAddresses * 2600; // Cold account access
        uint256 coldStorageCost = numStorageKeys * 2100; // Cold SLOAD
        coldAccessCost = coldAddressCost + coldStorageCost;

        // Access list upfront costs + warm access
        uint256 accessListCost = (numAddresses * 2400) + (numStorageKeys * 1900);
        uint256 warmAccessCost_ = (numAddresses * 100) + (numStorageKeys * 100);
        warmAccessCost = accessListCost + warmAccessCost_;

        // Net savings
        savings = int256(coldAccessCost) - int256(warmAccessCost);
    }

    /// @notice Check if access list is beneficial for given access pattern
    /// @param expectedAccessCount Number of times each slot is accessed
    /// @return beneficial True if access list provides gas savings
    function isAccessListBeneficial(
        uint256,
        /* numAddresses */
        uint256,
        /* numStorageKeys */
        uint256 expectedAccessCount
    )
        internal
        pure
        returns (bool beneficial)
    {
        // Access list is beneficial when:
        // - Storage is accessed multiple times (amortizes upfront cost)
        // - Large number of storage slots (bigger cold access penalty)
        // - expectedAccessCount > 1 usually makes it beneficial

        // Break-even analysis
        // Cold: 2600 per address + 2100 per slot (first access)
        //       100 per address + 100 per slot (subsequent)
        // Warm: 2400 per address + 1900 per slot (upfront)
        //       100 per address + 100 per slot (all accesses)

        // Savings per slot = (2100 - 100) * (expectedAccessCount - 1) - (1900 - 100)
        // Beneficial when: 2000 * (count - 1) > 1800
        // Simplified: count > 1.9, so beneficial when accessed twice or more

        beneficial = expectedAccessCount >= 2;
    }
}
