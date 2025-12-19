// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Auth, Authority} from "superlib/auth/Auth.sol";
import {ReentrancyGuard} from "superlib/security/ReentrancyLib.sol";

/// @title MaximumSecurityEngine
/// @notice Rate-limited execution with security score validation and dual whitelisting
/// @dev Uses Superlib Auth for role-based access control
contract MaximumSecurityEngine is Auth, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MAX_CALLS_PER_PERIOD = 10;
    uint256 public constant RATE_LIMIT_PERIOD = 60;
    uint256 public constant MAX_SECURITY_SCORE = 100;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    struct RateLimitInfo {
        uint256 callCount;
        uint256 periodStart;
    }

    struct SecurityConfig {
        uint256 minSecurityScore;
        bool requiresCommitment;
        uint256 maxValuePerCall;
    }

    mapping(address => RateLimitInfo) public rateLimits;
    mapping(address => uint256) public userSecurityScores;
    mapping(address => bool) public whitelistedTargets;
    mapping(address => mapping(bytes4 => bool)) public whitelistedSelectors;

    SecurityConfig public securityConfig;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event SecureExecutionComplete(address indexed user, address indexed target, bytes4 selector, bool success);
    event SecurityScoreUpdated(address indexed user, uint256 oldScore, uint256 newScore);
    event SecurityConfigUpdated(uint256 minScore, bool requiresCommitment, uint256 maxValue);
    event TargetWhitelistUpdated(address indexed target, bool status);
    event SelectorWhitelistUpdated(address indexed target, bytes4 selector, bool status);
    event RateLimitExceeded(address indexed user, uint256 callCount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error RateLimitExceededError(address user, uint256 callCount, uint256 maxCalls);
    error SecurityScoreTooLow(uint256 score, uint256 required);
    error TargetNotWhitelisted(address target);
    error SelectorNotWhitelisted(address target, bytes4 selector);
    error ValueExceedsMax(uint256 value, uint256 maxValue);
    error ZeroAddress();
    error ExecutionFailed();
    error InvalidSecurityScore(uint256 score);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, Authority _authority) Auth(_owner, _authority) {
        securityConfig = SecurityConfig({
            minSecurityScore: 50,
            requiresCommitment: false,
            maxValuePerCall: type(uint256).max
        });
    }

    /*//////////////////////////////////////////////////////////////
                          SECURE EXECUTION
    //////////////////////////////////////////////////////////////*/

    function executeWithMaximumSecurity(
        address target,
        bytes4 selector,
        bytes calldata params,
        address userAddress
    ) external nonReentrant requiresAuth returns (bool success, bytes memory result) {
        // Validate whitelists
        if (!whitelistedTargets[target]) revert TargetNotWhitelisted(target);
        if (!whitelistedSelectors[target][selector]) revert SelectorNotWhitelisted(target, selector);

        // Check security score
        uint256 score = userSecurityScores[userAddress];
        if (score < securityConfig.minSecurityScore) {
            revert SecurityScoreTooLow(score, securityConfig.minSecurityScore);
        }

        // Check and update rate limit
        RateLimitInfo storage rateLimit = rateLimits[userAddress];
        if (block.timestamp >= rateLimit.periodStart + RATE_LIMIT_PERIOD) {
            rateLimit.callCount = 1;
            rateLimit.periodStart = block.timestamp;
        } else {
            if (rateLimit.callCount >= MAX_CALLS_PER_PERIOD) {
                emit RateLimitExceeded(userAddress, rateLimit.callCount);
                revert RateLimitExceededError(userAddress, rateLimit.callCount, MAX_CALLS_PER_PERIOD);
            }
            rateLimit.callCount++;
        }

        // Build calldata and execute
        bytes memory callData = abi.encodePacked(selector, params);
        (success, result) = target.call(callData);
        
        if (!success) revert ExecutionFailed();

        emit SecureExecutionComplete(userAddress, target, selector, success);
    }

    /*//////////////////////////////////////////////////////////////
                         CONFIG MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function setSecurityConfig(
        uint256 minScore,
        bool requiresCommitment,
        uint256 maxValue
    ) external requiresAuth {
        if (minScore > MAX_SECURITY_SCORE) revert InvalidSecurityScore(minScore);
        
        securityConfig = SecurityConfig({
            minSecurityScore: minScore,
            requiresCommitment: requiresCommitment,
            maxValuePerCall: maxValue
        });

        emit SecurityConfigUpdated(minScore, requiresCommitment, maxValue);
    }

    function setUserSecurityScore(address user, uint256 score) external requiresAuth {
        if (user == address(0)) revert ZeroAddress();
        if (score > MAX_SECURITY_SCORE) revert InvalidSecurityScore(score);
        
        uint256 oldScore = userSecurityScores[user];
        userSecurityScores[user] = score;
        
        emit SecurityScoreUpdated(user, oldScore, score);
    }

    function setTargetWhitelist(address target, bool status) external requiresAuth {
        if (target == address(0)) revert ZeroAddress();
        whitelistedTargets[target] = status;
        emit TargetWhitelistUpdated(target, status);
    }

    function setSelectorWhitelist(address target, bytes4 selector, bool status) external requiresAuth {
        if (target == address(0)) revert ZeroAddress();
        whitelistedSelectors[target][selector] = status;
        emit SelectorWhitelistUpdated(target, selector, status);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getRateLimitStatus(address user) external view returns (uint256 remaining, uint256 resetTime) {
        RateLimitInfo memory info = rateLimits[user];
        uint256 periodEnd = info.periodStart + RATE_LIMIT_PERIOD;
        
        if (block.timestamp >= periodEnd) {
            return (MAX_CALLS_PER_PERIOD, block.timestamp);
        }
        
        remaining = MAX_CALLS_PER_PERIOD > info.callCount ? MAX_CALLS_PER_PERIOD - info.callCount : 0;
        resetTime = periodEnd;
    }

    function canExecute(address user, address target, bytes4 selector) external view returns (bool) {
        if (!whitelistedTargets[target]) return false;
        if (!whitelistedSelectors[target][selector]) return false;
        if (userSecurityScores[user] < securityConfig.minSecurityScore) return false;
        
        RateLimitInfo memory info = rateLimits[user];
        if (block.timestamp < info.periodStart + RATE_LIMIT_PERIOD) {
            if (info.callCount >= MAX_CALLS_PER_PERIOD) return false;
        }
        
        return true;
    }
}
