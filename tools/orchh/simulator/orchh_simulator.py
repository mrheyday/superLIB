#!/usr/bin/env python3
"""
ORCH-H Off-Chain Simulator (Skeleton)
Bytecode -> deterministic execution trace
"""

GAS_COST = {
    0x10: 1,   # HOLD
    0x11: 10,  # RAID
    0x12: 20,  # EXEC
    0x13: 5,   # ASSERT
    0x14: 10,  # WITHDRAW
    0x1F: 1,   # END
}

def simulate(program: bytes, gas_limit: int):
    gas_used = 0
    trace = []

    for pc, op in enumerate(program):
        if op not in GAS_COST:
            raise Exception(f"Invalid opcode {hex(op)}")

        gas_used += GAS_COST[op]
        if gas_used > gas_limit:
            raise Exception("Out of logical gas")

        trace.append({
            "pc": pc,
            "opcode": hex(op),
            "gas_used": gas_used
        })

        if op == 0x1F:
            break

    return trace

if __name__ == "__main__":
    print("ORCH-H simulator stub")
