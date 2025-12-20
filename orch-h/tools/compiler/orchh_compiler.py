#!/usr/bin/env python3
"""
ORCH-H Solver Compiler (Skeleton)
Intent -> ORCH-H bytecode
"""

OPCODES = {
    "HOLD": 0x10,
    "RAID": 0x11,
    "EXEC": 0x12,
    "ASSERT": 0x13,
    "WITHDRAW": 0x14,
    "END": 0x1F,
}

def compile_intent(intent):
    """
    intent: structured solver intent (dict / DSL)
    returns: bytes
    """
    program = bytearray()

    # Skeleton: deterministic ordering only
    for step in intent.get("steps", []):
        op = step["op"]
        if op not in OPCODES:
            raise ValueError(f"Unknown op {op}")
        program.append(OPCODES[op])

    program.append(OPCODES["END"])
    return bytes(program)

if __name__ == "__main__":
    print("ORCH-H compiler stub")
