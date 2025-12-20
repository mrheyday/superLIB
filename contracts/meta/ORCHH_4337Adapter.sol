// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract ORCHH_4337Adapter {
    error InvalidCaller();
    error ForwardFailed();

    address public immutable entryPoint;
    address public immutable executor;

    constructor(address _entryPoint, address _executor) {
        entryPoint = _entryPoint;
        executor = _executor;
    }

    function handleUserOp(address sender, bytes calldata orchProgram, uint256 nonce, bytes calldata signature) external {
        sender;
        if (msg.sender != entryPoint) revert InvalidCaller();

        (bool ok, ) = executor.call(
            abi.encodeWithSignature("execute(bytes,uint256,bytes)", orchProgram, nonce, signature)
        );
        if (!ok) revert ForwardFailed();
    }
}
