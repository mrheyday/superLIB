// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @notice Minimal read interface for Reserve-style trusted filler registries.
interface ITrustedFillerRegistryView {
    function isAllowed(
        address filler
    ) external view returns (bool);
}

/// @notice Minimal version interface implemented by Reserve-style trusted fillers.
interface ITrustedFillerVersionView {
    function version() external view returns (uint256);
}

/// @title  TrustedFillerPolicy
/// @author mev-arbitrum
/// @notice Deterministic admission helper for Reserve-derived trusted-filler lanes.
/// @dev    This deliberately does not import Reserve contracts. It extracts the
///         production-safe primitives this system needs: typed request hashing,
///         relayer binding, token/amount/deadline checks, registry allowlist
///         verification, filler-version floor, and collision-resistant salts.
library TrustedFillerPolicy {
    /// @notice EIP-712-compatible struct typehash for off-chain signatures and logs.
    bytes32 public constant FILL_REQUEST_TYPEHASH = 0xd4403fceffbfb9c14e7940bc4796c75dbe2f78fa90e949d40f8691c96ecfeaaa;

    bytes internal constant ACTIVE_FILLER_KEY_DOMAIN = "trusted-filler-active:";

    error TrustedFillerPolicy__ZeroAddress();
    error TrustedFillerPolicy__ZeroAmount();
    error TrustedFillerPolicy__SameToken();
    error TrustedFillerPolicy__RelayerMismatch();
    error TrustedFillerPolicy__DeadlineExpired();
    error TrustedFillerPolicy__RegistryMissing(address registry);
    error TrustedFillerPolicy__FillerMissing(address filler);
    error TrustedFillerPolicy__FillerNotAllowed(address filler);
    error TrustedFillerPolicy__FillerVersionTooLow(uint256 actualVersion, uint256 requiredVersion);

    /// @notice Coordinator/executor-side trusted-fill request.
    /// @param targetFiller   Trusted filler implementation or clone target.
    /// @param relayer        Exact caller expected to submit the fill.
    /// @param sellToken      Token being sold into the trusted filler.
    /// @param buyToken       Token expected back from the trusted filler.
    /// @param sellAmount     Exact sell amount committed by the admission policy.
    /// @param minBuyAmount   Minimum acceptable buy-token amount.
    /// @param deploymentSalt Caller-provided salt component for clone/create2 lanes.
    /// @param deadline       Last block timestamp at which request may be admitted.
    struct FillRequest {
        address targetFiller;
        address relayer;
        address sellToken;
        address buyToken;
        uint256 sellAmount;
        uint256 minBuyAmount;
        bytes32 deploymentSalt;
        uint256 deadline;
    }

    /// @notice ABI-hash the request against `FILL_REQUEST_TYPEHASH`.
    function hashFillRequest(
        FillRequest memory request
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                FILL_REQUEST_TYPEHASH,
                request.targetFiller,
                request.relayer,
                request.sellToken,
                request.buyToken,
                request.sellAmount,
                request.minBuyAmount,
                request.deploymentSalt,
                request.deadline
            )
        );
    }

    /// @notice Directional active-fill key for one sell/buy token pair.
    function activeFillerKey(
        address sellToken,
        address buyToken
    ) internal pure returns (bytes32) {
        if (sellToken == address(0) || buyToken == address(0)) revert TrustedFillerPolicy__ZeroAddress();
        if (sellToken == buyToken) revert TrustedFillerPolicy__SameToken();
        return keccak256(abi.encodePacked(ACTIVE_FILLER_KEY_DOMAIN, sellToken, buyToken));
    }

    /// @notice Reserve-compatible protected salt.
    /// @dev    Mirrors `keccak256(abi.encodePacked(msg.sender, senderSource, deploymentSalt))`
    ///         from Reserve's `TrustedFillerRegistry`, with explicit names for
    ///         deterministic off-chain/on-chain parity.
    function protectedSalt(
        address registryCaller,
        address senderSource,
        bytes32 deploymentSalt
    ) internal pure returns (bytes32) {
        if (registryCaller == address(0) || senderSource == address(0)) {
            revert TrustedFillerPolicy__ZeroAddress();
        }
        return keccak256(abi.encodePacked(registryCaller, senderSource, deploymentSalt));
    }

    /// @notice Validate request fields that do not need a registry read.
    function validateBasic(
        FillRequest memory request,
        address actualRelayer
    ) internal view {
        if (
            request.targetFiller == address(0) || request.relayer == address(0) || request.sellToken == address(0)
                || request.buyToken == address(0) || actualRelayer == address(0)
        ) revert TrustedFillerPolicy__ZeroAddress();
        if (request.sellAmount == 0 || request.minBuyAmount == 0) revert TrustedFillerPolicy__ZeroAmount();
        if (request.sellToken == request.buyToken) revert TrustedFillerPolicy__SameToken();
        if (request.relayer != actualRelayer) revert TrustedFillerPolicy__RelayerMismatch();
        if (block.timestamp > request.deadline) revert TrustedFillerPolicy__DeadlineExpired();
    }

    /// @notice Validate a trusted-fill request against a registry and filler version floor.
    /// @dev    This is a read-only admission gate. Capital-moving code should
    ///         still execute through its normal exact-calldata and profit gates.
    function validateTrustedFill(
        FillRequest memory request,
        address actualRelayer,
        address trustedFillerRegistry,
        uint256 minVersion
    ) internal view {
        validateBasic(request, actualRelayer);
        if (trustedFillerRegistry == address(0) || trustedFillerRegistry.code.length == 0) {
            revert TrustedFillerPolicy__RegistryMissing(trustedFillerRegistry);
        }
        if (request.targetFiller.code.length == 0) revert TrustedFillerPolicy__FillerMissing(request.targetFiller);
        if (!ITrustedFillerRegistryView(trustedFillerRegistry).isAllowed(request.targetFiller)) {
            revert TrustedFillerPolicy__FillerNotAllowed(request.targetFiller);
        }
        uint256 actualVersion = ITrustedFillerVersionView(request.targetFiller).version();
        if (actualVersion < minVersion) revert TrustedFillerPolicy__FillerVersionTooLow(actualVersion, minVersion);
    }
}
