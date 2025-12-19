// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Auth, Authority} from "superlib/auth/Auth.sol";
import {ReentrancyGuard} from "superlib/security/ReentrancyLib.sol";
import {SafeTransferLib} from "superlib/transfer/SafeTransferLib.sol";

/// @title FlashLoanEngine
/// @notice Manages flash loan providers and executes zero-capital arbitrage
/// @dev Uses Superlib Auth for role-based access control
contract FlashLoanEngine is Auth, ReentrancyGuard {

    using SafeTransferLib for address;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MAX_FEE_BPS = 500;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    struct FlashLoanProvider {
        address provider;
        uint256 feeBps;
        bool active;
    }

    mapping(bytes32 => FlashLoanProvider) public providers;
    bytes32[] public providerIds;
    mapping(address => bool) public whitelistedDexRouters;
    mapping(address => bool) public authorizedExecutors;

    uint256 public defaultSlippageBps = 50;
    uint256 public maxSlippageBps = 500;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ProviderAdded(bytes32 indexed providerId, address provider, uint256 feeBps);
    event ProviderRemoved(bytes32 indexed providerId);
    event ProviderUpdated(bytes32 indexed providerId, uint256 newFeeBps, bool active);
    event DexRouterWhitelistUpdated(address indexed router, bool status);
    event ExecutorUpdated(address indexed executor, bool status);
    event SlippageLimitsUpdated(uint256 defaultBps, uint256 maxBps);
    event FlashLoanExecuted(bytes32 indexed providerId, address indexed token, uint256 amount, uint256 fee);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error ProviderNotActive(bytes32 providerId);
    error ProviderAlreadyExists(bytes32 providerId);
    error ProviderNotFound(bytes32 providerId);
    error FeeExceedsMax(uint256 fee, uint256 maxFee);
    error DexNotWhitelisted(address dex);
    error ZeroAddress();
    error ZeroAmount();
    error SlippageExceedsMax(uint256 slippage, uint256 maxSlippage);
    error InsufficientProfit(uint256 profit, uint256 required);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _owner,
        Authority _authority
    ) Auth(_owner, _authority) {}

    /*//////////////////////////////////////////////////////////////
                         PROVIDER MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function addProvider(
        bytes32 providerId,
        address provider,
        uint256 feeBps
    ) external requiresAuth {
        if (provider == address(0)) revert ZeroAddress();
        if (feeBps > MAX_FEE_BPS) revert FeeExceedsMax(feeBps, MAX_FEE_BPS);
        if (providers[providerId].provider != address(0)) revert ProviderAlreadyExists(providerId);

        providers[providerId] = FlashLoanProvider({provider: provider, feeBps: feeBps, active: true});
        providerIds.push(providerId);

        emit ProviderAdded(providerId, provider, feeBps);
    }

    function removeProvider(
        bytes32 providerId
    ) external requiresAuth {
        if (providers[providerId].provider == address(0)) revert ProviderNotFound(providerId);

        delete providers[providerId];

        for (uint256 i = 0; i < providerIds.length; i++) {
            if (providerIds[i] == providerId) {
                providerIds[i] = providerIds[providerIds.length - 1];
                providerIds.pop();
                break;
            }
        }

        emit ProviderRemoved(providerId);
    }

    function updateProvider(
        bytes32 providerId,
        uint256 newFeeBps,
        bool active
    ) external requiresAuth {
        if (providers[providerId].provider == address(0)) revert ProviderNotFound(providerId);
        if (newFeeBps > MAX_FEE_BPS) revert FeeExceedsMax(newFeeBps, MAX_FEE_BPS);

        providers[providerId].feeBps = newFeeBps;
        providers[providerId].active = active;

        emit ProviderUpdated(providerId, newFeeBps, active);
    }

    /*//////////////////////////////////////////////////////////////
                         WHITELIST MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function setDexRouterWhitelist(
        address router,
        bool status
    ) external requiresAuth {
        if (router == address(0)) revert ZeroAddress();
        whitelistedDexRouters[router] = status;
        emit DexRouterWhitelistUpdated(router, status);
    }

    function setExecutorStatus(
        address executor,
        bool status
    ) external requiresAuth {
        if (executor == address(0)) revert ZeroAddress();
        authorizedExecutors[executor] = status;
        emit ExecutorUpdated(executor, status);
    }

    function setSlippageLimits(
        uint256 _defaultBps,
        uint256 _maxBps
    ) external requiresAuth {
        if (_defaultBps > _maxBps) revert SlippageExceedsMax(_defaultBps, _maxBps);
        defaultSlippageBps = _defaultBps;
        maxSlippageBps = _maxBps;
        emit SlippageLimitsUpdated(_defaultBps, _maxBps);
    }

    /*//////////////////////////////////////////////////////////////
                          FLASH LOAN EXECUTION
    //////////////////////////////////////////////////////////////*/

    function executeFlashLoanArbitrage(
        bytes32 providerId,
        address token,
        uint256 amount,
        address[] calldata dexPath,
        bytes[] calldata swapData,
        uint256 minProfit
    ) external nonReentrant requiresAuth returns (uint256 profit) {
        FlashLoanProvider memory provider = providers[providerId];
        if (!provider.active) revert ProviderNotActive(providerId);
        if (amount == 0) revert ZeroAmount();

        // Validate all DEXes are whitelisted
        for (uint256 i = 0; i < dexPath.length; i++) {
            if (!whitelistedDexRouters[dexPath[i]]) revert DexNotWhitelisted(dexPath[i]);
        }

        // Capture balance before
        uint256 balanceBefore = token.balanceOf(address(this));

        // Execute flash loan callback simulation
        // In production, this would call the provider's flash loan function
        // For now, we simulate the arbitrage execution
        for (uint256 i = 0; i < dexPath.length; i++) {
            (bool success,) = dexPath[i].call(swapData[i]);
            require(success, "SWAP_FAILED");
        }

        // Calculate profit
        uint256 balanceAfter = token.balanceOf(address(this));
        uint256 fee = (amount * provider.feeBps) / BPS_DENOMINATOR;

        if (balanceAfter < balanceBefore + fee) {
            profit = 0;
        } else {
            profit = balanceAfter - balanceBefore - fee;
        }

        if (profit < minProfit) revert InsufficientProfit(profit, minProfit);

        emit FlashLoanExecuted(providerId, token, amount, fee);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getProvider(
        bytes32 providerId
    ) external view returns (FlashLoanProvider memory) {
        return providers[providerId];
    }

    function getProviderCount() external view returns (uint256) {
        return providerIds.length;
    }

    function getAllProviderIds() external view returns (bytes32[] memory) {
        return providerIds;
    }

    function isProviderActive(
        bytes32 providerId
    ) external view returns (bool) {
        return providers[providerId].active;
    }

}
