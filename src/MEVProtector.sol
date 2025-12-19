// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Auth, Authority} from "superlib/auth/Auth.sol";
import {ReentrancyGuard} from "superlib/security/ReentrancyLib.sol";

/// @title MEVProtector
/// @notice Commit-reveal scheme with target/selector whitelisting for MEV protection
/// @dev Uses Superlib Auth for role-based access control
contract MEVProtector is Auth, ReentrancyGuard {

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant COMMIT_DELAY = 2;
    uint256 public constant COMMIT_EXPIRY = 50;
    uint256 public constant COOLDOWN_PERIOD = 60;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    struct Commitment {
        bytes32 hash;
        uint256 blockNumber;
    }

    mapping(address => Commitment) public commitments;
    mapping(address => uint256) public lastExecutionTime;
    mapping(address => bool) public whitelistedTargets;
    mapping(address => mapping(bytes4 => bool)) public whitelistedSelectors;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event CommitmentMade(address indexed user, bytes32 hash, uint256 blockNumber);
    event ProtectedExecutionComplete(address indexed user, address indexed target, bool success);
    event TargetWhitelistUpdated(address indexed target, bool status);
    event SelectorWhitelistUpdated(address indexed target, bytes4 selector, bool status);
    event ThreatDetected(address indexed source, string threatType);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error TargetNotWhitelisted(address target);
    error SelectorNotWhitelisted(address target, bytes4 selector);
    error NoCommitmentFound();
    error CommitmentTooRecent(uint256 currentBlock, uint256 commitBlock, uint256 required);
    error CommitmentExpired(uint256 currentBlock, uint256 commitBlock, uint256 expiry);
    error CommitmentMismatch(bytes32 expected, bytes32 provided);
    error CooldownActive(uint256 timeRemaining);
    error ZeroAddress();
    error ExecutionFailed();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _owner,
        Authority _authority
    ) Auth(_owner, _authority) {}

    /*//////////////////////////////////////////////////////////////
                           COMMIT-REVEAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function commitExecution(
        bytes32 commitHash
    ) external {
        commitments[msg.sender] = Commitment({hash: commitHash, blockNumber: block.number});
        emit CommitmentMade(msg.sender, commitHash, block.number);
    }

    function executeProtectedArbitrage(
        address target,
        bytes calldata data,
        bytes32 salt
    ) external nonReentrant requiresAuth returns (bool success, bytes memory result) {
        // Validate whitelist
        if (!whitelistedTargets[target]) revert TargetNotWhitelisted(target);

        bytes4 selector = bytes4(data[:4]);
        if (!whitelistedSelectors[target][selector]) revert SelectorNotWhitelisted(target, selector);

        // Validate commitment
        Commitment memory commitment = commitments[msg.sender];
        if (commitment.hash == bytes32(0)) revert NoCommitmentFound();

        uint256 blocksPassed = block.number - commitment.blockNumber;
        if (blocksPassed < COMMIT_DELAY) {
            revert CommitmentTooRecent(block.number, commitment.blockNumber, COMMIT_DELAY);
        }
        if (blocksPassed > COMMIT_EXPIRY) {
            revert CommitmentExpired(block.number, commitment.blockNumber, COMMIT_EXPIRY);
        }

        // Verify commitment matches
        bytes32 expectedHash = keccak256(abi.encodePacked(target, data, salt, msg.sender));
        if (commitment.hash != expectedHash) {
            emit ThreatDetected(msg.sender, "COMMITMENT_MISMATCH");
            revert CommitmentMismatch(commitment.hash, expectedHash);
        }

        // Check cooldown
        uint256 timeSinceLastExecution = block.timestamp - lastExecutionTime[msg.sender];
        if (timeSinceLastExecution < COOLDOWN_PERIOD) {
            revert CooldownActive(COOLDOWN_PERIOD - timeSinceLastExecution);
        }

        // Clear commitment and update execution time
        delete commitments[msg.sender];
        lastExecutionTime[msg.sender] = block.timestamp;

        // Execute
        (success, result) = target.call(data);
        if (!success) revert ExecutionFailed();

        emit ProtectedExecutionComplete(msg.sender, target, success);
    }

    /*//////////////////////////////////////////////////////////////
                         WHITELIST MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function setTargetWhitelist(
        address target,
        bool status
    ) external requiresAuth {
        if (target == address(0)) revert ZeroAddress();
        whitelistedTargets[target] = status;
        emit TargetWhitelistUpdated(target, status);
    }

    function setSelectorWhitelist(
        address target,
        bytes4 selector,
        bool status
    ) external requiresAuth {
        if (target == address(0)) revert ZeroAddress();
        whitelistedSelectors[target][selector] = status;
        emit SelectorWhitelistUpdated(target, selector, status);
    }

    function batchSetTargetWhitelist(
        address[] calldata targets,
        bool[] calldata statuses
    ) external requiresAuth {
        require(targets.length == statuses.length, "LENGTH_MISMATCH");
        for (uint256 i = 0; i < targets.length; i++) {
            if (targets[i] == address(0)) revert ZeroAddress();
            whitelistedTargets[targets[i]] = statuses[i];
            emit TargetWhitelistUpdated(targets[i], statuses[i]);
        }
    }

    function batchSetSelectorWhitelist(
        address[] calldata targets,
        bytes4[] calldata selectors,
        bool[] calldata statuses
    ) external requiresAuth {
        require(targets.length == selectors.length && selectors.length == statuses.length, "LENGTH_MISMATCH");
        for (uint256 i = 0; i < targets.length; i++) {
            if (targets[i] == address(0)) revert ZeroAddress();
            whitelistedSelectors[targets[i]][selectors[i]] = statuses[i];
            emit SelectorWhitelistUpdated(targets[i], selectors[i], statuses[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getCommitment(
        address user
    ) external view returns (bytes32 hash, uint256 blockNumber) {
        Commitment memory c = commitments[user];
        return (c.hash, c.blockNumber);
    }

    function canExecute(
        address user
    ) external view returns (bool) {
        Commitment memory c = commitments[user];
        if (c.hash == bytes32(0)) return false;
        uint256 blocksPassed = block.number - c.blockNumber;
        if (blocksPassed < COMMIT_DELAY || blocksPassed > COMMIT_EXPIRY) return false;
        uint256 timeSinceLastExecution = block.timestamp - lastExecutionTime[user];
        return timeSinceLastExecution >= COOLDOWN_PERIOD;
    }

}
