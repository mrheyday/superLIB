// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title ORCH-H ERC-4337 Adapter
/// @notice Bridges ERC-4337 UserOperation to ORCH-H executor
contract ORCHH_4337Adapter {
    error InvalidCaller();
    error InvalidExecutor();

    address public immutable entryPoint;
    address public immutable executor;

    constructor(address _entryPoint, address _executor) {
        entryPoint = _entryPoint;
        executor = _executor;
    }

    /// @notice Called by ERC-4337 EntryPoint
    function handleUserOp(
        address sender,
        bytes calldata orchProgram,
        uint256 nonce,
        bytes calldata signature
    ) external {
        if (msg.sender != entryPoint) revert InvalidCaller();

        (bool ok, ) = executor.call(
            abi.encodeWithSignature(
                "execute(bytes,uint256,bytes)",
                orchProgram,
                nonce,
                signature
            )
        );

        if (!ok) revert InvalidExecutor();
    }
}
