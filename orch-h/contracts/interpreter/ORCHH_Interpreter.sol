// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title ORCH-H Opcode Interpreter (Skeleton)
/// @notice Executes validated ORCH-H bytecode
library ORCHH_Interpreter {
    error OutOfGas();
    error UnknownOpcode();

    uint256 internal constant GAS_HOLD     = 1;
    uint256 internal constant GAS_RAID     = 10;
    uint256 internal constant GAS_EXEC     = 20;
    uint256 internal constant GAS_ASSERT   = 5;
    uint256 internal constant GAS_WITHDRAW = 10;
    uint256 internal constant GAS_END      = 1;

    function execute(bytes calldata program, uint256 gasLimit)
        internal
        pure
    {
        uint256 gasUsed;

        for (uint256 pc = 0; pc < program.length; pc++) {
            uint8 op = uint8(program[pc]);

            if (op == 0x10) { // HOLD
                gasUsed += GAS_HOLD;
            }
            else if (op == 0x11) { // RAID
                gasUsed += GAS_RAID;
            }
            else if (op == 0x12) { // EXEC
                gasUsed += GAS_EXEC;
            }
            else if (op == 0x13) { // ASSERT
                gasUsed += GAS_ASSERT;
            }
            else if (op == 0x14) { // WITHDRAW
                gasUsed += GAS_WITHDRAW;
            }
            else if (op == 0x1F) { // END
                gasUsed += GAS_END;
                break;
            }
            else {
                revert UnknownOpcode();
            }

            if (gasUsed > gasLimit) revert OutOfGas();
        }
    }
}
