// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @title HookCreate2
/// @notice Minimal CREATE2 helper for deploying mined Uniswap v4 hook addresses.
/// @dev Adapted from Hookmate's deploy-helper pattern, pinned to Solidity 0.8.34.
library HookCreate2 {
    error HookCreate2__EmptyInitCode();
    error HookCreate2__DeploymentFailed(bytes revertData);

    /// @notice Deploy `initCode` with CREATE2 and an explicit salt.
    /// @param initCode Full contract creation bytecode.
    /// @param salt CREATE2 salt, usually produced by an off-chain hook-address miner.
    /// @return deployed Contract address created by CREATE2.
    function deploy(
        bytes memory initCode,
        bytes32 salt
    ) internal returns (address deployed) {
        if (initCode.length == 0) revert HookCreate2__EmptyInitCode();
        assembly ("memory-safe") {
            deployed := create2(0, add(initCode, 0x20), mload(initCode), salt)
        }
        if (deployed == address(0)) {
            bytes memory revertData;
            assembly ("memory-safe") {
                let size := returndatasize()
                revertData := mload(0x40)
                mstore(revertData, size)
                let end := add(add(revertData, 0x20), size)
                mstore(0x40, and(add(end, 0x1f), not(0x1f)))
                returndatacopy(add(revertData, 0x20), 0, size)
            }
            revert HookCreate2__DeploymentFailed(revertData);
        }
    }

    /// @notice Predict a CREATE2 address for this deployer.
    function predict(
        bytes32 initCodeHash,
        bytes32 salt
    ) internal view returns (address predicted) {
        return predict(address(this), initCodeHash, salt);
    }

    /// @notice Predict a CREATE2 address for an arbitrary deployer.
    function predict(
        address deployer,
        bytes32 initCodeHash,
        bytes32 salt
    ) internal pure returns (address predicted) {
        predicted = address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash)))));
    }
}
