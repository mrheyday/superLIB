// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Auth, Authority} from "superlib/auth/Auth.sol";
import {ReentrancyGuard} from "superlib/security/ReentrancyLib.sol";
import {SafeTransferLib} from "superlib/transfer/SafeTransferLib.sol";

/// @title UltimateArbitrageEngine
/// @notice Executes zero-capital arbitrage with flash loan pool whitelisting
/// @dev Uses Superlib Auth for role-based access control
contract UltimateArbitrageEngine is Auth, ReentrancyGuard {
using SafeTransferLib for address;

/*//////////////////////////////////////////////////////////////
STORAGE
//////////////////////////////////////////////////////////////*/

mapping(address => bool) public whitelistedFlashLoanPools;
mapping(address => bool) public authorizedExecutors;

address public feeVault;
uint256 public performanceFeeBps = 1000; // 10%

/*//////////////////////////////////////////////////////////////
EVENTS
//////////////////////////////////////////////////////////////*/

event FlashLoanPoolWhitelisted(address indexed pool, bool status);
event ExecutorAuthorized(address indexed executor, bool status);
event ArbitrageExecuted(address indexed executor, address indexed token, uint256 profit, uint256 fee);
event FeeVaultUpdated(address indexed oldVault, address indexed newVault);
event PerformanceFeeUpdated(uint256 oldFee, uint256 newFee);

/*//////////////////////////////////////////////////////////////
ERRORS
//////////////////////////////////////////////////////////////*/

error PoolNotWhitelisted(address pool);
error ZeroAddress();
error ZeroProfit();
error ExecutionFailed();
error InvalidFee(uint256 fee);

/*//////////////////////////////////////////////////////////////
CONSTRUCTOR
//////////////////////////////////////////////////////////////*/

constructor(address _owner, Authority _authority, address _feeVault) Auth(_owner, _authority) {
if (_feeVault == address(0)) revert ZeroAddress();
feeVault = _feeVault;
}

/*//////////////////////////////////////////////////////////////
WHITELIST MANAGEMENT
//////////////////////////////////////////////////////////////*/

function setFlashLoanPoolWhitelist(address pool, bool status) external requiresAuth {
if (pool == address(0)) revert ZeroAddress();
whitelistedFlashLoanPools[pool] = status;
emit FlashLoanPoolWhitelisted(pool, status);
}

function setExecutorAuthorization(address executor, bool status) external requiresAuth {
if (executor == address(0)) revert ZeroAddress();
authorizedExecutors[executor] = status;
emit ExecutorAuthorized(executor, status);
}

function setFeeVault(address _feeVault) external requiresAuth {
if (_feeVault == address(0)) revert ZeroAddress();
emit FeeVaultUpdated(feeVault, _feeVault);
feeVault = _feeVault;
}

function setPerformanceFee(uint256 feeBps) external requiresAuth {
if (feeBps > 5000) revert InvalidFee(feeBps); // Max 50%
emit PerformanceFeeUpdated(performanceFeeBps, feeBps);
performanceFeeBps = feeBps;
}

/*//////////////////////////////////////////////////////////////
ARBITRAGE EXECUTION
//////////////////////////////////////////////////////////////*/

function executeArbitrage(address flashLoanPool, address token, uint256 amount, bytes calldata arbitrageData)
external
nonReentrant
requiresAuth
returns (uint256 profit)
{
if (!whitelistedFlashLoanPools[flashLoanPool]) revert PoolNotWhitelisted(flashLoanPool);

// Capture balance before
uint256 balanceBefore = token.balanceOf(address(this));

// Execute flash loan and arbitrage
(bool success,) = flashLoanPool.call(arbitrageData);
if (!success) revert ExecutionFailed();

// Calculate profit
uint256 balanceAfter = token.balanceOf(address(this));
if (balanceAfter <= balanceBefore) revert ZeroProfit();

profit = balanceAfter - balanceBefore;

// Take performance fee
uint256 fee = (profit * performanceFeeBps) / 10_000;
if (fee > 0) {
token.safeTransfer(feeVault, fee);
}

emit ArbitrageExecuted(msg.sender, token, profit, fee);
}

/*//////////////////////////////////////////////////////////////
CALLBACK HANDLER
//////////////////////////////////////////////////////////////*/

function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data)
external
returns (bytes32)
{
if (!whitelistedFlashLoanPools[msg.sender]) revert PoolNotWhitelisted(msg.sender);

// Execute arbitrage logic from data
(bool success,) = address(this).call(data);
if (!success) revert ExecutionFailed();

// Repay flash loan
uint256 repayAmount = amount + fee;
token.safeTransfer(msg.sender, repayAmount);

return keccak256("ERC3156FlashBorrower.onFlashLoan");
}

/*//////////////////////////////////////////////////////////////
VIEW FUNCTIONS
//////////////////////////////////////////////////////////////*/

function isPoolWhitelisted(address pool) external view returns (bool) {
return whitelistedFlashLoanPools[pool];
}

function isExecutorAuthorized(address executor) external view returns (bool) {
return authorizedExecutors[executor];
}
}
