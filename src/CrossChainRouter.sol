// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Auth, Authority} from "superlib/auth/Auth.sol";
import {ReentrancyGuard} from "superlib/security/ReentrancyLib.sol";
import {SafeTransferLib} from "superlib/transfer/SafeTransferLib.sol";

/// @title CrossChainRouter
/// @notice Manages cross-chain trade execution with timelock-protected configuration
/// @dev Uses Superlib Auth for role-based access control
contract CrossChainRouter is Auth, ReentrancyGuard {
    using SafeTransferLib for address;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant CONFIG_TIMELOCK = 24 hours;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    struct ChainConfig {
        address bridge;
        uint256 minAmount;
        uint256 maxAmount;
        bool active;
    }

    struct PendingConfig {
        ChainConfig config;
        uint256 executeAfter;
        bool exists;
    }

    mapping(uint256 => ChainConfig) public chainConfigs;
    mapping(uint256 => PendingConfig) public pendingConfigs;
    mapping(uint256 => uint256) public dailyVolume;
    mapping(uint256 => uint256) public dailyVolumeLimit;
    mapping(uint256 => uint256) public lastVolumeReset;

    uint256[] public supportedChains;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ChainConfigQueued(uint256 indexed chainId, address bridge, uint256 minAmount, uint256 maxAmount, uint256 executeAfter);
    event ChainConfigExecuted(uint256 indexed chainId, address bridge, uint256 minAmount, uint256 maxAmount);
    event ChainConfigCancelled(uint256 indexed chainId);
    event DailyLimitUpdated(uint256 indexed chainId, uint256 newLimit);
    event CrossChainTradeExecuted(uint256 indexed chainId, address indexed token, uint256 amount, bytes32 messageId);
    event DailyVolumeReset(uint256 indexed chainId, uint256 timestamp);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error ChainNotActive(uint256 chainId);
    error ConfigTimelockActive(uint256 chainId, uint256 executeAfter, uint256 currentTime);
    error NoPendingConfig(uint256 chainId);
    error AmountBelowMinimum(uint256 amount, uint256 minimum);
    error AmountAboveMaximum(uint256 amount, uint256 maximum);
    error DailyVolumeLimitExceeded(uint256 requested, uint256 remaining);
    error ZeroAddress();
    error InvalidChainId();
    error BridgeCallFailed();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, Authority _authority) Auth(_owner, _authority) {}

    /*//////////////////////////////////////////////////////////////
                      TIMELOCK CONFIG MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function queueChainConfig(
        uint256 chainId,
        address bridge,
        uint256 minAmount,
        uint256 maxAmount,
        bool active
    ) external requiresAuth {
        if (bridge == address(0)) revert ZeroAddress();
        if (chainId == 0) revert InvalidChainId();

        uint256 executeAfter = block.timestamp + CONFIG_TIMELOCK;

        pendingConfigs[chainId] = PendingConfig({
            config: ChainConfig({
                bridge: bridge,
                minAmount: minAmount,
                maxAmount: maxAmount,
                active: active
            }),
            executeAfter: executeAfter,
            exists: true
        });

        emit ChainConfigQueued(chainId, bridge, minAmount, maxAmount, executeAfter);
    }

    function executeChainConfig(uint256 chainId) external requiresAuth {
        PendingConfig memory pending = pendingConfigs[chainId];
        if (!pending.exists) revert NoPendingConfig(chainId);
        if (block.timestamp < pending.executeAfter) {
            revert ConfigTimelockActive(chainId, pending.executeAfter, block.timestamp);
        }

        // Check if this is a new chain
        bool isNew = chainConfigs[chainId].bridge == address(0);
        if (isNew) {
            supportedChains.push(chainId);
        }

        chainConfigs[chainId] = pending.config;
        delete pendingConfigs[chainId];

        emit ChainConfigExecuted(chainId, pending.config.bridge, pending.config.minAmount, pending.config.maxAmount);
    }

    function cancelPendingConfig(uint256 chainId) external requiresAuth {
        if (!pendingConfigs[chainId].exists) revert NoPendingConfig(chainId);
        delete pendingConfigs[chainId];
        emit ChainConfigCancelled(chainId);
    }

    function setDailyLimit(uint256 chainId, uint256 limit) external requiresAuth {
        dailyVolumeLimit[chainId] = limit;
        emit DailyLimitUpdated(chainId, limit);
    }

    /*//////////////////////////////////////////////////////////////
                         CROSS-CHAIN EXECUTION
    //////////////////////////////////////////////////////////////*/

    function executeCrossChainTrade(
        uint256 chainId,
        address token,
        uint256 amount,
        bytes calldata bridgeData
    ) external nonReentrant requiresAuth returns (bytes32 messageId) {
        ChainConfig memory config = chainConfigs[chainId];
        if (!config.active) revert ChainNotActive(chainId);
        if (amount < config.minAmount) revert AmountBelowMinimum(amount, config.minAmount);
        if (amount > config.maxAmount) revert AmountAboveMaximum(amount, config.maxAmount);

        // Reset daily volume if new day
        _resetDailyVolumeIfNeeded(chainId);

        // Check daily limit
        uint256 limit = dailyVolumeLimit[chainId];
        if (limit > 0) {
            uint256 remaining = limit > dailyVolume[chainId] ? limit - dailyVolume[chainId] : 0;
            if (amount > remaining) revert DailyVolumeLimitExceeded(amount, remaining);
            dailyVolume[chainId] += amount;
        }

        // Transfer tokens to bridge
        token.safeTransferFrom(msg.sender, config.bridge, amount);

        // Call bridge with provided data
        (bool success, bytes memory result) = config.bridge.call(bridgeData);
        if (!success) revert BridgeCallFailed();

        // Extract message ID from result if available
        if (result.length >= 32) {
            messageId = abi.decode(result, (bytes32));
        } else {
            messageId = keccak256(abi.encodePacked(chainId, token, amount, block.timestamp));
        }

        emit CrossChainTradeExecuted(chainId, token, amount, messageId);
    }

    function _resetDailyVolumeIfNeeded(uint256 chainId) internal {
        uint256 today = block.timestamp / 1 days;
        if (lastVolumeReset[chainId] < today) {
            dailyVolume[chainId] = 0;
            lastVolumeReset[chainId] = today;
            emit DailyVolumeReset(chainId, block.timestamp);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getChainConfig(uint256 chainId) external view returns (ChainConfig memory) {
        return chainConfigs[chainId];
    }

    function getPendingConfig(uint256 chainId) external view returns (PendingConfig memory) {
        return pendingConfigs[chainId];
    }

    function getSupportedChains() external view returns (uint256[] memory) {
        return supportedChains;
    }

    function getRemainingDailyVolume(uint256 chainId) external view returns (uint256) {
        uint256 limit = dailyVolumeLimit[chainId];
        if (limit == 0) return type(uint256).max;
        
        uint256 today = block.timestamp / 1 days;
        if (lastVolumeReset[chainId] < today) return limit;
        
        return limit > dailyVolume[chainId] ? limit - dailyVolume[chainId] : 0;
    }

    function isChainActive(uint256 chainId) external view returns (bool) {
        return chainConfigs[chainId].active;
    }
}
