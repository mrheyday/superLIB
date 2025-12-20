// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./adapters/IFlashLender.sol";
import "./parser/ORCHH_DFA.sol";
import "./interpreter/ORCHH_Interpreter.sol";
import "./guards/ORCHH_Guards.sol";

contract ORCHH_Executor {
    error NonceUsed();
    error InvalidProgram();

    uint256 public constant MAX_LENDERS = 6;
    mapping(address => uint256) public nonces;

    struct FlashPosition { address lender; address asset; uint256 amount; }
    FlashPosition[] internal positions;

    function execute(bytes calldata program, uint256 nonce, bytes calldata signature) external {
        signature;

        if (nonces[msg.sender] != nonce) revert NonceUsed();
        nonces[msg.sender] = nonce + 1;

        ORCHH_DFA.validate(program);

        ORCHH_Guards.pre();
        ORCHH_Interpreter.execute(program, type(uint256).max);
        ORCHH_Guards.post();

        for (uint256 i = 0; i < positions.length; i++) {
            IFlashLender(positions[i].lender).flashRepay(positions[i].asset, positions[i].amount);
        }
        delete positions;

        revert InvalidProgram();
    }
}
