// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

interface ISwapRouter {
  function exactInput(
    bytes calldata path,
    address recipient,
    uint256 deadline,
    uint256 amountIn,
    uint256 amountOutMinimum
  ) external payable returns (uint256);
}

error SwapFailed();
error TransferFailed();
error DeadlineExceeded();

/// @title DelegatedExecutor
/// @notice Contract for EIP-7702 EOA delegation
/// @dev Allows EOA to execute swaps without pre-deployment via account code delegation
contract DelegatedExecutor {
  // Uniswap V3 SwapRouter02 on Arbitrum
  address constant SWAP_ROUTER = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

  event Swap(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
  event Delegated(address indexed eoa, bytes32 nonce);

  /// @notice Execute swap via EIP-7702 delegation
  /// @dev Called when EOA code points to this contract (via SetCode tx)
  /// @param tokenIn Input token
  /// @param amountIn Input amount
  /// @param path Encoded swap path
  /// @param minAmountOut Minimum output
  /// @param deadline Tx deadline
  function executeSwap(
    address tokenIn,
    uint256 amountIn,
    bytes calldata path,
    uint256 minAmountOut,
    uint256 deadline
  ) external returns (uint256 amountOut) {
    if (block.timestamp > deadline) revert DeadlineExceeded();

    // Transfer tokens from EOA (msg.sender) - use SafeERC20
    SafeERC20.safeTransferFrom(IERC20(tokenIn), msg.sender, address(this), amountIn);

    // Approve router with SafeERC20
    SafeERC20.forceApprove(IERC20(tokenIn), SWAP_ROUTER, amountIn);

    // Execute swap
    try
      ISwapRouter(SWAP_ROUTER).exactInput(path, msg.sender, deadline, amountIn, minAmountOut)
    returns (uint256 out) {
      amountOut = out;
    } catch {
      revert SwapFailed();
    }

    emit Swap(tokenIn, _getTokenOut(path), amountIn, amountOut);
  }

  /// @notice Multi-hop swap with callback support
  /// @dev Advanced execution for complex paths
  function executeSwapWithCallback(
    address tokenIn,
    uint256 amountIn,
    bytes calldata path,
    uint256 minAmountOut,
    uint256 deadline,
    bytes calldata callbackData
  ) external returns (uint256 amountOut) {
    if (block.timestamp > deadline) revert DeadlineExceeded();

    SafeERC20.safeTransferFrom(IERC20(tokenIn), msg.sender, address(this), amountIn);
    SafeERC20.forceApprove(IERC20(tokenIn), SWAP_ROUTER, amountIn);

    try
      ISwapRouter(SWAP_ROUTER).exactInput(path, address(this), deadline, amountIn, minAmountOut)
    returns (uint256 out) {
      amountOut = out;
    } catch {
      revert SwapFailed();
    }

    // Handle callback for additional operations
    if (callbackData.length > 0) {
      _executeCallback(callbackData, amountOut);
    }

    // Transfer output to EOA - use SafeERC20
    address tokenOut = _getTokenOut(path);
    SafeERC20.safeTransfer(IERC20(tokenOut), msg.sender, amountOut);

    emit Swap(tokenIn, tokenOut, amountIn, amountOut);
  }

  /// @notice Batch execute multiple swaps atomically
  /// @dev All swaps execute in order; if one fails, entire transaction reverts
  struct SwapRequest {
    address tokenIn;
    uint256 amountIn;
    bytes path;
    uint256 minAmountOut;
  }

  function executeBatchSwaps(
    SwapRequest[] calldata swaps,
    uint256 deadline
  ) external returns (uint256[] memory amountsOut) {
    if (block.timestamp > deadline) revert DeadlineExceeded();

    amountsOut = new uint256[](swaps.length);

    for (uint256 i = 0; i < swaps.length; ++i) {
      SwapRequest calldata swap = swaps[i];

      // Transfer input from EOA - use SafeERC20
      SafeERC20.safeTransferFrom(IERC20(swap.tokenIn), msg.sender, address(this), swap.amountIn);

      // Approve and execute
      SafeERC20.forceApprove(IERC20(swap.tokenIn), SWAP_ROUTER, swap.amountIn);

      try
        ISwapRouter(SWAP_ROUTER).exactInput(
          swap.path,
          msg.sender,
          deadline,
          swap.amountIn,
          swap.minAmountOut
        )
      returns (uint256 out) {
        amountsOut[i] = out;
      } catch {
        revert SwapFailed();
      }

      emit Swap(swap.tokenIn, _getTokenOut(swap.path), swap.amountIn, amountsOut[i]);
    }
  }

  /// @notice Receive tokens (for fallback swaps)
  receive() external payable {}

  /// @dev Internal: execute callback for custom logic
  function _executeCallback(bytes calldata callbackData, uint256 amountOut) internal {
    (bool success,) = address(this).call(callbackData);
    require(success, 'Callback failed');
  }

  /// @dev Internal: extract output token from Uniswap V3 path
  function _getTokenOut(bytes calldata path) internal pure returns (address) {
    require(path.length >= 20, 'Invalid path');
    return address(bytes20(path[path.length - 20:]));
  }
}
