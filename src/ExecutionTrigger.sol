// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Auth, Authority} from "superlib/auth/Auth.sol";

/// @title ExecutionTrigger
/// @notice Manages conditional execution triggers with bounded arrays
/// @dev Uses Superlib Auth for role-based access control
contract ExecutionTrigger is Auth {

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MAX_TRIGGERS = 50;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    enum TriggerType {
        PriceThreshold,
        TimeInterval,
        VolumeSpike,
        VolatilityBreakout,
        LiquidityEvent
    }

    struct Trigger {
        bytes32 triggerId;
        TriggerType triggerType;
        uint256 threshold;
        uint256 cooldown;
        uint256 lastTriggered;
        bool active;
    }

    mapping(bytes32 => Trigger) public triggers;
    bytes32[] public triggerIds;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event TriggerAdded(bytes32 indexed triggerId, TriggerType triggerType, uint256 threshold);
    event TriggerRemoved(bytes32 indexed triggerId);
    event TriggerUpdated(bytes32 indexed triggerId, uint256 newThreshold, uint256 newCooldown);
    event TriggerToggled(bytes32 indexed triggerId, bool active);
    event TriggerFired(bytes32 indexed triggerId, uint256 timestamp);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error MaxTriggersReached(uint256 current, uint256 max);
    error TriggerNotFound(bytes32 triggerId);
    error TriggerAlreadyExists(bytes32 triggerId);
    error TriggerOnCooldown(bytes32 triggerId, uint256 remainingTime);
    error TriggerNotActive(bytes32 triggerId);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _owner,
        Authority _authority
    ) Auth(_owner, _authority) {}

    /*//////////////////////////////////////////////////////////////
                        TRIGGER MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function addTrigger(
        bytes32 triggerId,
        TriggerType triggerType,
        uint256 threshold,
        uint256 cooldown
    ) external requiresAuth {
        if (triggerIds.length >= MAX_TRIGGERS) {
            revert MaxTriggersReached(triggerIds.length, MAX_TRIGGERS);
        }
        if (triggers[triggerId].threshold != 0 || triggers[triggerId].active) {
            revert TriggerAlreadyExists(triggerId);
        }

        triggers[triggerId] = Trigger({
            triggerId: triggerId,
            triggerType: triggerType,
            threshold: threshold,
            cooldown: cooldown,
            lastTriggered: 0,
            active: true
        });

        triggerIds.push(triggerId);
        emit TriggerAdded(triggerId, triggerType, threshold);
    }

    function removeTrigger(
        bytes32 triggerId
    ) external requiresAuth {
        if (triggers[triggerId].threshold == 0 && !triggers[triggerId].active) {
            revert TriggerNotFound(triggerId);
        }

        delete triggers[triggerId];

        for (uint256 i = 0; i < triggerIds.length; i++) {
            if (triggerIds[i] == triggerId) {
                triggerIds[i] = triggerIds[triggerIds.length - 1];
                triggerIds.pop();
                break;
            }
        }

        emit TriggerRemoved(triggerId);
    }

    function updateThreshold(
        bytes32 triggerId,
        uint256 newThreshold
    ) external requiresAuth {
        if (triggers[triggerId].threshold == 0 && !triggers[triggerId].active) {
            revert TriggerNotFound(triggerId);
        }
        triggers[triggerId].threshold = newThreshold;
        emit TriggerUpdated(triggerId, newThreshold, triggers[triggerId].cooldown);
    }

    function updateCooldown(
        bytes32 triggerId,
        uint256 newCooldown
    ) external requiresAuth {
        if (triggers[triggerId].threshold == 0 && !triggers[triggerId].active) {
            revert TriggerNotFound(triggerId);
        }
        triggers[triggerId].cooldown = newCooldown;
        emit TriggerUpdated(triggerId, triggers[triggerId].threshold, newCooldown);
    }

    function toggleTrigger(
        bytes32 triggerId,
        bool active
    ) external requiresAuth {
        if (triggers[triggerId].threshold == 0 && !triggers[triggerId].active) {
            revert TriggerNotFound(triggerId);
        }
        triggers[triggerId].active = active;
        emit TriggerToggled(triggerId, active);
    }

    /*//////////////////////////////////////////////////////////////
                        TRIGGER EXECUTION
    //////////////////////////////////////////////////////////////*/

    function checkAndExecuteTriggers(
        uint256 currentValue
    ) external requiresAuth returns (bytes32[] memory firedTriggers) {
        uint256 firedCount = 0;
        bytes32[] memory tempFired = new bytes32[](triggerIds.length);

        for (uint256 i = 0; i < triggerIds.length; i++) {
            bytes32 id = triggerIds[i];
            Trigger storage trigger = triggers[id];

            if (!trigger.active) continue;

            // Check cooldown
            if (block.timestamp < trigger.lastTriggered + trigger.cooldown) continue;

            // Check threshold
            if (currentValue >= trigger.threshold) {
                trigger.lastTriggered = block.timestamp;
                tempFired[firedCount++] = id;
                emit TriggerFired(id, block.timestamp);
            }
        }

        // Copy to correctly sized array
        firedTriggers = new bytes32[](firedCount);
        for (uint256 i = 0; i < firedCount; i++) {
            firedTriggers[i] = tempFired[i];
        }
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getTrigger(
        bytes32 triggerId
    ) external view returns (Trigger memory) {
        return triggers[triggerId];
    }

    function getTriggerCount() external view returns (uint256) {
        return triggerIds.length;
    }

    function getActiveTriggers() external view returns (bytes32[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < triggerIds.length; i++) {
            if (triggers[triggerIds[i]].active) activeCount++;
        }

        bytes32[] memory active = new bytes32[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < triggerIds.length; i++) {
            if (triggers[triggerIds[i]].active) {
                active[index++] = triggerIds[i];
            }
        }
        return active;
    }

    function canTriggerFire(
        bytes32 triggerId,
        uint256 currentValue
    ) external view returns (bool) {
        Trigger memory trigger = triggers[triggerId];
        if (!trigger.active) return false;
        if (block.timestamp < trigger.lastTriggered + trigger.cooldown) return false;
        return currentValue >= trigger.threshold;
    }

}
