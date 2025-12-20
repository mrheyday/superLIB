// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library ORCHH_DFA {
    error InvalidTransition();
    error TooManyRaids();
    error MismatchedRepayment();
    error MissingEnd();

    enum State { START, RAIDING, EXECUTING, ASSERTING, REPAYING, END }

    uint8 internal constant OP_RAID     = 0x11;
    uint8 internal constant OP_EXEC     = 0x12;
    uint8 internal constant OP_ASSERT   = 0x13;
    uint8 internal constant OP_WITHDRAW = 0x14;
    uint8 internal constant OP_END      = 0x1F;

    function validate(bytes calldata program) internal pure {
        State state = State.START;
        uint256 raids;
        uint256 repays;

        for (uint256 i = 0; i < program.length; i++) {
            uint8 op = uint8(program[i]);

            if (op == OP_RAID) {
                if (state != State.START && state != State.RAIDING) revert InvalidTransition();
                state = State.RAIDING;
                raids++;
                if (raids > 6) revert TooManyRaids();
            } else if (op == OP_EXEC) {
                if (state != State.RAIDING && state != State.EXECUTING) revert InvalidTransition();
                state = State.EXECUTING;
            } else if (op == OP_ASSERT) {
                if (state != State.EXECUTING && state != State.ASSERTING) revert InvalidTransition();
                state = State.ASSERTING;
            } else if (op == OP_WITHDRAW) {
                if (state != State.ASSERTING && state != State.REPAYING) revert InvalidTransition();
                state = State.REPAYING;
                repays++;
            } else if (op == OP_END) {
                if (state != State.REPAYING) revert InvalidTransition();
                state = State.END;
            } else {
                revert InvalidTransition();
            }
        }

        if (state != State.END) revert MissingEnd();
        if (raids != repays) revert MismatchedRepayment();
    }
}
