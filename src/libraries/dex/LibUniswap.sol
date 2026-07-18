// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title LibUniswap
/// @notice Deterministic address computation for Uniswap V2/V3 pools.
library LibUniswap {
    /// @dev Arbitrum One V3 pool init code hash.
    bytes32 internal constant V3_POOL_INIT_CODE_HASH =
        0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;
    /// @dev Arbitrum One Sushiswap V2 pair init code hash.
    bytes32 internal constant V2_PAIR_INIT_CODE_HASH =
        0xe18a34eb0f55c3c04145d80d1e4ca51e60f06e67614e59f4f46927d63659223a;

    /// @notice Computes the deterministic address of a Uniswap V3 pool.
    function computeV3Address(
        address factory,
        address tokenA,
        address tokenB,
        uint24 fee
    ) internal pure returns (address pool) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        pool = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff", factory, keccak256(abi.encode(token0, token1, fee)), V3_POOL_INIT_CODE_HASH
                        )
                    )
                )
            )
        );
    }

    /// @notice Computes the deterministic address of a Uniswap V2 pair.
    function computeV2Address(
        address factory,
        address tokenA,
        address tokenB
    ) internal pure returns (address pair) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff", factory, keccak256(abi.encodePacked(token0, token1)), V2_PAIR_INIT_CODE_HASH
                        )
                    )
                )
            )
        );
    }
}
