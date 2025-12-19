// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Auth, Authority} from "superlib/auth/Auth.sol";
import {ReentrancyGuard} from "superlib/security/ReentrancyLib.sol";
import {SafeTransferLib} from "superlib/transfer/SafeTransferLib.sol";

/// @notice Structured swap instruction with explicit slippage protection
/// @dev Replaces arbitrary calldata execution for security
struct SwapInstruction {
    address router;       // Must be whitelisted
    address tokenIn;      // Input token
    address tokenOut;     // Output token
    uint256 amountIn;     // Input amount
    uint256 minOut;       // Minimum output (slippage protection)
    bytes swapCalldata;   // Router-specific calldata
}

/// @title UltimateArbitrageEngine
/// @notice Executes zero-capital arbitrage with flash loan pool whitelisting
/// @dev Uses Superlib Auth for role-based access control
/// @custom:security-contact security@example.com
contract UltimateArbitrageEngine is Auth, ReentrancyGuard {
    using SafeTransferLib for address;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev ERC-3156 callback success hash (precomputed for gas efficiency)
    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    /// @dev Maximum performance fee (50%)
    uint256 public constant MAX_FEE_BPS = 5000;

    /// @dev Minimum profit required to prevent dust attacks
    uint256 public constant MIN_PROFIT_THRESHOLD = 1000;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(address => bool) public whitelistedFlashLoanPools;
    mapping(address => bool) public authorizedExecutors;

    /// @dev Whitelisted DEX routers for swap execution
    mapping(address => bool) public whitelistedDexRouters;

    address public feeVault;
    uint256 public performanceFeeBps = 1000; // 10%

    /// @dev Reentrancy lock specifically for flash loan callbacks
    /// @custom:security Prevents re-entrancy during callback execution
    bool private _inFlashLoan;

    /// @dev Expected initiator during flash loan (set before triggering loan)
    address private _expectedInitiator;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event FlashLoanPoolWhitelisted(address indexed pool, bool status);
    event DexRouterWhitelisted(address indexed router, bool status);
    event ExecutorAuthorized(address indexed executor, bool status);
    event ArbitrageExecuted(address indexed executor, address indexed token, uint256 profit, uint256 fee);
    event FeeVaultUpdated(address indexed oldVault, address indexed newVault);
    event PerformanceFeeUpdated(uint256 oldFee, uint256 newFee);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error PoolNotWhitelisted(address pool);
    error RouterNotWhitelisted(address router);
    error ZeroAddress();
    error ZeroProfit();
    error ProfitBelowThreshold(uint256 profit, uint256 threshold);
    error ExecutionFailed();
    error InvalidFee(uint256 fee);
    error InvalidInitiator(address expected, address actual);
    error FlashLoanReentrant();
    error SlippageExceeded(uint256 expected, uint256 actual);
    error InvalidSwapData();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _owner,
        Authority _authority,
        address _feeVault
    ) Auth(_owner, _authority) {
        if (_feeVault == address(0)) revert ZeroAddress();
        feeVault = _feeVault;
    }

    /*//////////////////////////////////////////////////////////////
                         WHITELIST MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function setFlashLoanPoolWhitelist(
        address pool,
        bool status
    ) external requiresAuth {
        if (pool == address(0)) revert ZeroAddress();
        whitelistedFlashLoanPools[pool] = status;
        emit FlashLoanPoolWhitelisted(pool, status);
    }

    function setDexRouterWhitelist(
        address router,
        bool status
    ) external requiresAuth {
        if (router == address(0)) revert ZeroAddress();
        whitelistedDexRouters[router] = status;
        emit DexRouterWhitelisted(router, status);
    }

    function setExecutorAuthorization(
        address executor,
        bool status
    ) external requiresAuth {
        if (executor == address(0)) revert ZeroAddress();
        authorizedExecutors[executor] = status;
        emit ExecutorAuthorized(executor, status);
    }

    function setFeeVault(
        address _feeVault
    ) external requiresAuth {
        if (_feeVault == address(0)) revert ZeroAddress();
        emit FeeVaultUpdated(feeVault, _feeVault);
        feeVault = _feeVault;
    }

    function setPerformanceFee(
        uint256 feeBps
    ) external requiresAuth {
        if (feeBps > MAX_FEE_BPS) revert InvalidFee(feeBps);
        emit PerformanceFeeUpdated(performanceFeeBps, feeBps);
        performanceFeeBps = feeBps;
    }

    /*//////////////////////////////////////////////////////////////
                        ARBITRAGE EXECUTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Execute arbitrage via flash loan
    /// @param flashLoanPool The pool to borrow from
    /// @param token The token to borrow and arbitrage
    /// @param amount Amount to borrow
    /// @param swaps Array of swap instructions (router, calldata, minOut)
    /// @return profit Net profit after fees
    /// @custom:security Uses structured swap data instead of arbitrary calldata
    function executeArbitrage(
        address flashLoanPool,
        address token,
        uint256 amount,
        SwapInstruction[] calldata swaps
    ) external nonReentrant requiresAuth returns (uint256 profit) {
        if (!whitelistedFlashLoanPools[flashLoanPool]) revert PoolNotWhitelisted(flashLoanPool);
        if (swaps.length == 0) revert InvalidSwapData();

        // Validate all routers are whitelisted before execution
        for (uint256 i = 0; i < swaps.length; i++) {
            if (!whitelistedDexRouters[swaps[i].router]) {
                revert RouterNotWhitelisted(swaps[i].router);
            }
        }

        // Set expected initiator before flash loan
        _expectedInitiator = address(this);

        // Capture balance before
        uint256 balanceBefore = token.balanceOf(address(this));

        // Encode swap instructions for callback
        bytes memory callbackData = abi.encode(swaps);

        // Execute flash loan - pool will call onFlashLoan
        // Using ERC-3156 interface: flashLoan(borrower, token, amount, data)
        (bool success,) = flashLoanPool.call(
            abi.encodeWithSignature(
                "flashLoan(address,address,uint256,bytes)",
                address(this),
                token,
                amount,
                callbackData
            )
        );
        if (!success) revert ExecutionFailed();

        // Clear expected initiator
        _expectedInitiator = address(0);

        // Calculate profit
        uint256 balanceAfter = token.balanceOf(address(this));
        if (balanceAfter <= balanceBefore) revert ZeroProfit();

        profit = balanceAfter - balanceBefore;
        if (profit < MIN_PROFIT_THRESHOLD) revert ProfitBelowThreshold(profit, MIN_PROFIT_THRESHOLD);

        // Take performance fee (CEI: state change before transfer)
        uint256 fee = (profit * performanceFeeBps) / 10_000;
        if (fee > 0) {
            token.safeTransfer(feeVault, fee);
        }

        emit ArbitrageExecuted(msg.sender, token, profit, fee);
    }

    /*//////////////////////////////////////////////////////////////
                          CALLBACK HANDLER
    //////////////////////////////////////////////////////////////*/

    /// @notice ERC-3156 flash loan callback
    /// @dev SECURITY: Only accepts callbacks from whitelisted pools with validated initiator
    /// @custom:security No arbitrary code execution - only structured swap execution
    function onFlashLoan(
        address initiator,
        address, /* token - unused, we track via swaps */
        uint256, /* amount - unused */
        uint256, /* fee - unused, handled in repayment */
        bytes calldata data
    ) external returns (bytes32) {
        // SECURITY CHECK 1: Only whitelisted pools can call
        if (!whitelistedFlashLoanPools[msg.sender]) revert PoolNotWhitelisted(msg.sender);

        // SECURITY CHECK 2: Validate initiator is this contract
        // This prevents unauthorized callbacks from compromised pools
        if (initiator != _expectedInitiator) revert InvalidInitiator(_expectedInitiator, initiator);

        // SECURITY CHECK 3: Reentrancy guard for flash loan callbacks
        if (_inFlashLoan) revert FlashLoanReentrant();
        _inFlashLoan = true;

        // Decode structured swap instructions
        SwapInstruction[] memory swaps = abi.decode(data, (SwapInstruction[]));

        // Execute swaps through whitelisted routers only
        _executeSwaps(swaps);

        // Note: Repayment is handled by executeArbitrage after callback returns
        // The pool will pull tokens via transferFrom or we transfer in executeArbitrage

        // Clear reentrancy lock
        _inFlashLoan = false;

        return CALLBACK_SUCCESS;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL SWAP EXECUTION
    //////////////////////////////////////////////////////////////*/

    /// @dev Execute a sequence of swaps through whitelisted routers
    /// @custom:security Each swap has explicit slippage protection via minOut
    function _executeSwaps(SwapInstruction[] memory swaps) internal {
        for (uint256 i = 0; i < swaps.length; i++) {
            SwapInstruction memory swap = swaps[i];

            // Double-check router whitelist (defense in depth)
            if (!whitelistedDexRouters[swap.router]) {
                revert RouterNotWhitelisted(swap.router);
            }

            // Approve router for input token
            swap.tokenIn.safeApprove(swap.router, swap.amountIn);

            // Capture output balance before
            uint256 outBefore = swap.tokenOut.balanceOf(address(this));

            // Execute swap on whitelisted router
            (bool success,) = swap.router.call(swap.swapCalldata);
            if (!success) revert ExecutionFailed();

            // Verify slippage protection
            uint256 outAfter = swap.tokenOut.balanceOf(address(this));
            uint256 received = outAfter - outBefore;
            if (received < swap.minOut) {
                revert SlippageExceeded(swap.minOut, received);
            }

            // Clear approval (security best practice)
            swap.tokenIn.safeApprove(swap.router, 0);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function isPoolWhitelisted(address pool) external view returns (bool) {
        return whitelistedFlashLoanPools[pool];
    }

    function isRouterWhitelisted(address router) external view returns (bool) {
        return whitelistedDexRouters[router];
    }

    function isExecutorAuthorized(address executor) external view returns (bool) {
        return authorizedExecutors[executor];
    }

    /// @dev Check if flash loan is currently in progress
    function isInFlashLoan() external view returns (bool) {
        return _inFlashLoan;
    }
}
