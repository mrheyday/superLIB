#!/usr/bin/env python3
"""
ORCH-H Signing Tool (Stub)
Produces EIP-712 program commitments
"""

from eth_utils import keccak

def program_hash(chain_id, executor, nonce, program_bytes):
    return keccak(
        chain_id.to_bytes(32, "big") +
        bytes.fromhex(executor[2:]) +
        nonce.to_bytes(32, "big") +
        program_bytes
    )

if __name__ == "__main__":
    print("ORCH-H signing stub")
