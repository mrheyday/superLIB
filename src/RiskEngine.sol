// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Auth, Authority} from "superlib/auth/Auth.sol";
import {MathLib} from "superlib/utils/MathLib.sol";

/// @title RiskEngine
/// @notice Calculates and validates risk scores for arbitrage operations
/// @dev Uses Superlib Auth for role-based access control
contract RiskEngine is Auth {
    using MathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MAX_RISK_SCORE = 100;
    uint256 public constant MIN_RISK_SCORE = 0;
    uint256 public constant DEFAULT_RISK_SCORE = 50;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    struct RiskParams {
        uint256 volatilityWeight;
        uint256 liquidityWeight;
        uint256 correlationWeight;
        uint256 timeDecayFactor;
    }

    mapping(address => uint256) public tokenRiskScores;
    mapping(bytes32 => uint256) public pairRiskScores;

    RiskParams public riskParams;
    uint256 public globalRiskMultiplier = 100; // 100 = 1x

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event TokenRiskScoreUpdated(address indexed token, uint256 oldScore, uint256 newScore);
    event PairRiskScoreUpdated(bytes32 indexed pairId, uint256 oldScore, uint256 newScore);
    event RiskParamsUpdated(
        uint256 volatilityWeight, uint256 liquidityWeight, uint256 correlationWeight, uint256 timeDecay
    );
    event GlobalRiskMultiplierUpdated(uint256 oldMultiplier, uint256 newMultiplier);
    event RiskEvaluated(address indexed token, uint256 amount, uint256 score);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidRiskScore(uint256 score);
    error ZeroAddress();
    error InvalidWeight();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner, Authority _authority) Auth(_owner, _authority) {
        riskParams = RiskParams({volatilityWeight: 30, liquidityWeight: 40, correlationWeight: 20, timeDecayFactor: 10});
    }

    /*//////////////////////////////////////////////////////////////
                          RISK CALCULATION
    //////////////////////////////////////////////////////////////*/

    function evaluate(
        address token,
        uint256 amount,
        uint256 /* deadline */
    )
        external
        view
        returns (uint256 score)
    {
        uint256 baseScore = tokenRiskScores[token];
        if (baseScore == 0) baseScore = DEFAULT_RISK_SCORE;

        // Apply amount-based adjustment (larger amounts = higher risk)
        uint256 amountAdjustment = _calculateAmountAdjustment(amount);

        // Calculate final score with global multiplier
        score = (baseScore + amountAdjustment) * globalRiskMultiplier / 100;

        // Clamp to valid range
        score = score.clamp(MIN_RISK_SCORE, MAX_RISK_SCORE);

        return score;
    }

    function evaluatePair(address tokenA, address tokenB, uint256 amountA, uint256 amountB)
        external
        view
        returns (uint256 score)
    {
        bytes32 pairId = _getPairId(tokenA, tokenB);

        uint256 pairScore = pairRiskScores[pairId];
        if (pairScore == 0) {
            // Calculate from individual token scores
            uint256 scoreA = tokenRiskScores[tokenA];
            uint256 scoreB = tokenRiskScores[tokenB];
            if (scoreA == 0) scoreA = DEFAULT_RISK_SCORE;
            if (scoreB == 0) scoreB = DEFAULT_RISK_SCORE;
            pairScore = (scoreA + scoreB) / 2;
        }

        uint256 totalAmount = amountA + amountB;
        uint256 amountAdjustment = _calculateAmountAdjustment(totalAmount);

        score = (pairScore + amountAdjustment) * globalRiskMultiplier / 100;
        score = score.clamp(MIN_RISK_SCORE, MAX_RISK_SCORE);
    }

    function evaluateBatch(address[] calldata tokens, uint256[] calldata amounts)
        external
        view
        returns (uint256[] memory scores)
    {
        require(tokens.length == amounts.length, "LENGTH_MISMATCH");

        scores = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 baseScore = tokenRiskScores[tokens[i]];
            if (baseScore == 0) baseScore = DEFAULT_RISK_SCORE;

            uint256 amountAdjustment = _calculateAmountAdjustment(amounts[i]);
            scores[i] =
                ((baseScore + amountAdjustment) * globalRiskMultiplier / 100).clamp(MIN_RISK_SCORE, MAX_RISK_SCORE);
        }
    }

    function _calculateAmountAdjustment(uint256 amount) internal pure returns (uint256) {
        // Simple log-based adjustment: larger amounts add more risk
        if (amount == 0) return 0;
        if (amount < 1e18) return 0;
        if (amount < 1e20) return 5;
        if (amount < 1e22) return 10;
        if (amount < 1e24) return 15;
        return 20;
    }

    function _getPairId(address tokenA, address tokenB) internal pure returns (bytes32) {
        return
            tokenA < tokenB ? keccak256(abi.encodePacked(tokenA, tokenB)) : keccak256(abi.encodePacked(tokenB, tokenA));
    }

    /*//////////////////////////////////////////////////////////////
                         CONFIG MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function setTokenRiskScore(address token, uint256 score) external requiresAuth {
        if (token == address(0)) revert ZeroAddress();
        if (score > MAX_RISK_SCORE) revert InvalidRiskScore(score);

        uint256 oldScore = tokenRiskScores[token];
        tokenRiskScores[token] = score;

        emit TokenRiskScoreUpdated(token, oldScore, score);
    }

    function setPairRiskScore(address tokenA, address tokenB, uint256 score) external requiresAuth {
        if (tokenA == address(0) || tokenB == address(0)) revert ZeroAddress();
        if (score > MAX_RISK_SCORE) revert InvalidRiskScore(score);

        bytes32 pairId = _getPairId(tokenA, tokenB);
        uint256 oldScore = pairRiskScores[pairId];
        pairRiskScores[pairId] = score;

        emit PairRiskScoreUpdated(pairId, oldScore, score);
    }

    function setRiskParams(
        uint256 volatilityWeight,
        uint256 liquidityWeight,
        uint256 correlationWeight,
        uint256 timeDecayFactor
    ) external requiresAuth {
        if (volatilityWeight + liquidityWeight + correlationWeight + timeDecayFactor != 100) {
            revert InvalidWeight();
        }

        riskParams = RiskParams({
            volatilityWeight: volatilityWeight,
            liquidityWeight: liquidityWeight,
            correlationWeight: correlationWeight,
            timeDecayFactor: timeDecayFactor
        });

        emit RiskParamsUpdated(volatilityWeight, liquidityWeight, correlationWeight, timeDecayFactor);
    }

    function setGlobalRiskMultiplier(uint256 multiplier) external requiresAuth {
        uint256 oldMultiplier = globalRiskMultiplier;
        globalRiskMultiplier = multiplier;
        emit GlobalRiskMultiplierUpdated(oldMultiplier, multiplier);
    }

    function batchSetTokenRiskScores(address[] calldata tokens, uint256[] calldata scores) external requiresAuth {
        require(tokens.length == scores.length, "LENGTH_MISMATCH");

        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(0)) revert ZeroAddress();
            if (scores[i] > MAX_RISK_SCORE) revert InvalidRiskScore(scores[i]);

            uint256 oldScore = tokenRiskScores[tokens[i]];
            tokenRiskScores[tokens[i]] = scores[i];
            emit TokenRiskScoreUpdated(tokens[i], oldScore, scores[i]);
        }
    }
}
