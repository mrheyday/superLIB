// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Auth, Authority} from "superlib/auth/Auth.sol";

/// @title IntelligenceProcessor
/// @notice Processes and stores arbitrage opportunity intelligence
/// @dev Uses Superlib Auth for role-based access control
contract IntelligenceProcessor is Auth {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MAX_OPPORTUNITIES_PER_TYPE = 1000;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    enum OpportunityType {
        PriceDiscrepancy,
        LiquidityImbalance,
        YieldDifferential,
        CrossChainArb,
        MEVExtraction
    }

    struct Opportunity {
        bytes32 opportunityId;
        OpportunityType oppType;
        uint256 estimatedProfit;
        uint256 riskScore;
        uint256 expiryTime;
        bool processed;
    }

    mapping(bytes32 => Opportunity) public opportunities;
    mapping(OpportunityType => bytes32[]) public opportunitiesByType;
    mapping(OpportunityType => uint256) public opportunityCount;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event OpportunityAdded(bytes32 indexed opportunityId, OpportunityType oppType, uint256 estimatedProfit);
    event OpportunityProcessed(bytes32 indexed opportunityId, bool success);
    event OpportunitiesCleared(OpportunityType oppType, uint256 count);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error MaxOpportunitiesReached(OpportunityType oppType);
    error OpportunityNotFound(bytes32 opportunityId);
    error OpportunityExpired(bytes32 opportunityId);
    error OpportunityAlreadyProcessed(bytes32 opportunityId);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, Authority _authority) Auth(_owner, _authority) {}

    /*//////////////////////////////////////////////////////////////
                     OPPORTUNITY MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function addOpportunity(
        bytes32 opportunityId,
        OpportunityType oppType,
        uint256 estimatedProfit,
        uint256 riskScore,
        uint256 expiryTime
    ) external requiresAuth {
        if (opportunityCount[oppType] >= MAX_OPPORTUNITIES_PER_TYPE) {
            revert MaxOpportunitiesReached(oppType);
        }

        opportunities[opportunityId] = Opportunity({
            opportunityId: opportunityId,
            oppType: oppType,
            estimatedProfit: estimatedProfit,
            riskScore: riskScore,
            expiryTime: expiryTime,
            processed: false
        });

        opportunitiesByType[oppType].push(opportunityId);
        opportunityCount[oppType]++;

        emit OpportunityAdded(opportunityId, oppType, estimatedProfit);
    }

    function markProcessed(bytes32 opportunityId, bool success) external requiresAuth {
        Opportunity storage opp = opportunities[opportunityId];
        if (opp.estimatedProfit == 0 && opp.expiryTime == 0) {
            revert OpportunityNotFound(opportunityId);
        }
        if (opp.processed) revert OpportunityAlreadyProcessed(opportunityId);
        if (block.timestamp > opp.expiryTime) revert OpportunityExpired(opportunityId);

        opp.processed = true;
        emit OpportunityProcessed(opportunityId, success);
    }

    function clearExpiredOpportunities(OpportunityType oppType) external requiresAuth {
        bytes32[] storage typeOpps = opportunitiesByType[oppType];
        uint256 cleared = 0;

        for (uint256 i = typeOpps.length; i > 0; i--) {
            bytes32 id = typeOpps[i - 1];
            if (block.timestamp > opportunities[id].expiryTime || opportunities[id].processed) {
                delete opportunities[id];
                typeOpps[i - 1] = typeOpps[typeOpps.length - 1];
                typeOpps.pop();
                cleared++;
            }
        }

        opportunityCount[oppType] -= cleared;
        emit OpportunitiesCleared(oppType, cleared);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getOpportunity(bytes32 opportunityId) external view returns (Opportunity memory) {
        return opportunities[opportunityId];
    }

    function getOpportunitiesByType(OpportunityType oppType) external view returns (bytes32[] memory) {
        return opportunitiesByType[oppType];
    }

    function getActiveOpportunities(OpportunityType oppType) external view returns (bytes32[] memory) {
        bytes32[] memory typeOpps = opportunitiesByType[oppType];
        uint256 activeCount = 0;

        for (uint256 i = 0; i < typeOpps.length; i++) {
            Opportunity memory opp = opportunities[typeOpps[i]];
            if (!opp.processed && block.timestamp <= opp.expiryTime) {
                activeCount++;
            }
        }

        bytes32[] memory active = new bytes32[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < typeOpps.length; i++) {
            Opportunity memory opp = opportunities[typeOpps[i]];
            if (!opp.processed && block.timestamp <= opp.expiryTime) {
                active[index++] = typeOpps[i];
            }
        }
        return active;
    }
}
