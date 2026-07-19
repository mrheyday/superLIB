// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {ORCHH_Executor} from "../../src/orchh/ORCHH_Executor.sol";
import {ORCHH_ASPRegistry} from "../../src/orchh/ORCHH_ASPRegistry.sol";
import {ORCHH_4337Adapter} from "../../src/orchh/meta/ORCHH_4337Adapter.sol";
import {ORCHH_DFA} from "../../src/orchh/parser/ORCHH_DFA.sol";
import {ORCHH_Interpreter} from "../../src/orchh/interpreter/ORCHH_Interpreter.sol";

/// @dev The DFA/Interpreter libraries are `internal`, so we forward calldata through
///      thin external harnesses to drive them from tests.
contract DFAHarness {
    function validate(bytes calldata program) external pure {
        ORCHH_DFA.validate(program);
    }
}

contract InterpHarness {
    function execute(bytes calldata program, uint256 gasLimit) external pure {
        ORCHH_Interpreter.execute(program, gasLimit);
    }
}

/// @notice Test-drive of the consolidated ORCH-H calldata-obfuscation subsystem (src/orchh).
///         Exercises the FSM grammar, interpreter gas/opcode accounting, the ASP registry's
///         access + domain gating, and documents the executor's wired-but-always-reverting skeleton.
contract ORCHHTest is Test {
    DFAHarness dfa;
    InterpHarness interp;

    // Minimal well-formed program: RAID -> EXEC -> ASSERT -> WITHDRAW -> END (raids == repays == 1).
    bytes internal constant VALID_PROGRAM = hex"111213141f";

    function setUp() public {
        dfa = new DFAHarness();
        interp = new InterpHarness();
    }

    /* ------------------------------- DFA (parser) ------------------------------- */

    function test_DFA_AcceptsWellFormedProgram() public view {
        dfa.validate(VALID_PROGRAM); // must not revert
    }

    function test_DFA_RejectsBadStartTransition() public {
        vm.expectRevert(ORCHH_DFA.InvalidTransition.selector);
        dfa.validate(hex"12"); // EXEC before any RAID
    }

    function test_DFA_RejectsMissingEnd() public {
        vm.expectRevert(ORCHH_DFA.MissingEnd.selector);
        dfa.validate(hex"11121314"); // no END opcode
    }

    function test_DFA_RejectsMismatchedRepayment() public {
        // two RAIDs, single WITHDRAW -> reaches END but raids(2) != repays(1)
        vm.expectRevert(ORCHH_DFA.MismatchedRepayment.selector);
        dfa.validate(hex"11111213141f");
    }

    function test_DFA_RejectsTooManyRaids() public {
        vm.expectRevert(ORCHH_DFA.TooManyRaids.selector);
        dfa.validate(hex"11111111111111"); // 7 RAID opcodes (> 6)
    }

    function test_DFA_RejectsUnknownOpcode() public {
        vm.expectRevert(ORCHH_DFA.InvalidTransition.selector);
        dfa.validate(hex"99");
    }

    /* ---------------------------- Interpreter (VM) ---------------------------- */

    function test_Interp_RunsWithinGasBudget() public view {
        interp.execute(hex"101f", type(uint256).max); // HOLD, END
    }

    function test_Interp_RevertsOnGasExhaustion() public {
        // RAID(10) already exceeds a budget of 5
        vm.expectRevert(ORCHH_Interpreter.OutOfGas.selector);
        interp.execute(hex"1112", 5);
    }

    function test_Interp_RevertsOnUnknownOpcode() public {
        vm.expectRevert(ORCHH_Interpreter.UnknownOpcode.selector);
        interp.execute(hex"99", type(uint256).max);
    }

    /* ------------------------------- Executor -------------------------------- */

    /// @dev Documents the current skeleton: a *valid* program still terminates in
    ///      `InvalidProgram()` because the executor ends with an unconditional revert.
    function test_Executor_ValidProgramStillRevertsSkeleton() public {
        ORCHH_Executor exec = new ORCHH_Executor();
        vm.expectRevert(ORCHH_Executor.InvalidProgram.selector);
        exec.execute(VALID_PROGRAM, 0, "");
    }

    function test_Executor_RejectsWrongNonce() public {
        ORCHH_Executor exec = new ORCHH_Executor();
        vm.expectRevert(ORCHH_Executor.NonceUsed.selector);
        exec.execute(VALID_PROGRAM, 5, ""); // caller nonce is 0, not 5
    }

    /* ------------------------------ ASP Registry ----------------------------- */

    function test_ASP_ConstructorRejectsZeroAddress() public {
        vm.expectRevert(ORCHH_ASPRegistry.ZeroAddress.selector);
        new ORCHH_ASPRegistry(address(0), address(0xBEEF));
    }

    function test_ASP_SetResolveRoundTrip() public {
        address admin = address(0xA11CE);
        ORCHH_ASPRegistry reg = new ORCHH_ASPRegistry(admin, address(this));
        vm.prank(admin);
        reg.setASP(0x20, address(0xCAFE)); // 0x20 == LSP domain start
        assertEq(reg.resolve(0x20), address(0xCAFE));
    }

    function test_ASP_SetRejectsNonAdmin() public {
        ORCHH_ASPRegistry reg = new ORCHH_ASPRegistry(address(0xA11CE), address(this));
        vm.expectRevert(ORCHH_ASPRegistry.InvalidASPByte.selector); // wrong-caller guard
        reg.setASP(0x20, address(0xCAFE));
    }

    function test_ASP_SetRejectsOutOfDomainKey() public {
        address admin = address(0xA11CE);
        ORCHH_ASPRegistry reg = new ORCHH_ASPRegistry(admin, address(this));
        vm.prank(admin);
        vm.expectRevert(ORCHH_ASPRegistry.OutOfDomain.selector);
        reg.setASP(0x00, address(0xCAFE)); // 0x00 outside all ASP domains
    }

    function test_ASP_ResolveForExecGatedToExecutor() public {
        ORCHH_ASPRegistry reg = new ORCHH_ASPRegistry(address(0xA11CE), address(0xE0));
        vm.expectRevert(ORCHH_ASPRegistry.WrongExecutor.selector);
        reg.resolveForExec(0x20); // caller is test, not the executor
    }

    /* ----------------------------- 4337 Adapter ------------------------------ */

    function test_4337_RejectsNonEntryPointCaller() public {
        ORCHH_4337Adapter adapter = new ORCHH_4337Adapter(address(0xE411), address(0xDEAD));
        vm.expectRevert(ORCHH_4337Adapter.InvalidCaller.selector);
        adapter.handleUserOp(address(this), VALID_PROGRAM, 0, "");
    }

    function test_4337_EntryPointForwardsAndBubblesExecutorRevert() public {
        ORCHH_Executor exec = new ORCHH_Executor();
        address entryPoint = address(0xE411);
        ORCHH_4337Adapter adapter = new ORCHH_4337Adapter(entryPoint, address(exec));
        // Executor skeleton always reverts -> low-level call fails -> ForwardFailed.
        vm.prank(entryPoint);
        vm.expectRevert(ORCHH_4337Adapter.ForwardFailed.selector);
        adapter.handleUserOp(address(this), VALID_PROGRAM, 0, "");
    }
}
