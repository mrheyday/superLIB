// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @notice Minimal interface for Reserve Protocol's UniversalDeployer.
interface IReserveUniversalDeployer {
    function deployIfNotDeployed(
        bytes32 salt,
        bytes memory initCode,
        bytes calldata initializer
    ) external payable returns (address deployedAddress);
}

/// @title UniversalDeployment
/// @notice Deterministic deployment helper compatible with Reserve's UniversalDeployer salt model.
/// @dev Salts encode the caller/deployer in the high 20 bytes and a uint96 discriminator in the low bytes.
library UniversalDeployment {
    address internal constant RESERVE_UNIVERSAL_DEPLOYER = 0x7A7371751Ccb2a38b0794182a1b812D054a5FB85;
    uint256 internal constant DISCRIMINATOR_MASK = type(uint96).max;

    error UniversalDeployment__ZeroAddress();
    error UniversalDeployment__EmptyInitCode();
    error UniversalDeployment__DiscriminatorTooLarge();
    error UniversalDeployment__UniversalDeployerMissing(address deployer);

    /// @notice Salt scoped to `deployer` and the current chain id.
    function saltForChain(
        address deployer
    ) internal view returns (bytes32) {
        return salt(deployer, block.chainid);
    }

    /// @notice Salt scoped to `deployer` and chain-independent discriminator zero.
    function universalSalt(
        address deployer
    ) internal pure returns (bytes32) {
        return salt(deployer, 0);
    }

    /// @notice Salt with caller/deployer encoded into the high 20 bytes.
    function salt(
        address deployer,
        uint256 discriminator
    ) internal pure returns (bytes32) {
        if (deployer == address(0)) revert UniversalDeployment__ZeroAddress();
        if (discriminator > DISCRIMINATOR_MASK) revert UniversalDeployment__DiscriminatorTooLarge();
        return bytes32((uint256(uint160(deployer)) << 96) | discriminator);
    }

    /// @notice Hash committed by Reserve's deployer for idempotent deployments.
    function deploymentHash(
        bytes32 saltValue,
        bytes memory initCode,
        bytes memory initializer
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(saltValue, keccak256(initCode), keccak256(initializer)));
    }

    /// @notice Predict deployment address through the canonical Reserve UniversalDeployer.
    function predict(
        bytes32 saltValue,
        bytes32 initCodeHash
    ) internal pure returns (address) {
        return predictAt(RESERVE_UNIVERSAL_DEPLOYER, saltValue, initCodeHash);
    }

    /// @notice Predict deployment address through a specified UniversalDeployer-compatible contract.
    function predictAt(
        address universalDeployer,
        bytes32 saltValue,
        bytes32 initCodeHash
    ) internal pure returns (address) {
        if (universalDeployer == address(0)) revert UniversalDeployment__ZeroAddress();
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), universalDeployer, saltValue, initCodeHash))))
        );
    }

    /// @notice Deploy through the canonical Reserve UniversalDeployer.
    function createDeployment(
        bytes32 saltValue,
        bytes memory initCode,
        bytes memory initializer
    ) internal returns (address) {
        return createDeploymentAt(RESERVE_UNIVERSAL_DEPLOYER, saltValue, initCode, initializer, 0);
    }

    /// @notice Deploy through the canonical Reserve UniversalDeployer and forward ETH to initializer.
    function createDeployment(
        bytes32 saltValue,
        bytes memory initCode,
        bytes memory initializer,
        uint256 value
    ) internal returns (address) {
        return createDeploymentAt(RESERVE_UNIVERSAL_DEPLOYER, saltValue, initCode, initializer, value);
    }

    /// @notice Deploy through a specified UniversalDeployer-compatible contract.
    function createDeploymentAt(
        address universalDeployer,
        bytes32 saltValue,
        bytes memory initCode,
        bytes memory initializer,
        uint256 value
    ) internal returns (address) {
        if (universalDeployer == address(0)) revert UniversalDeployment__ZeroAddress();
        if (initCode.length == 0) revert UniversalDeployment__EmptyInitCode();
        if (universalDeployer.code.length == 0) {
            revert UniversalDeployment__UniversalDeployerMissing(universalDeployer);
        }
        return IReserveUniversalDeployer(universalDeployer).deployIfNotDeployed{ value: value }(
            saltValue, initCode, initializer
        );
    }
}
