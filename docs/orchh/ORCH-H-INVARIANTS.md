# ORCH-H Formal Invariants
Version: 0.7  
Checkpoint: 7  
Status: CORE SECTIONS LOCKED

---

## 1. Scope

This document enumerates **formal invariants** that MUST hold for all
valid ORCH-H executions.

No new behavior is introduced in this checkpoint.

---

## 2. Global Invariants (LOCKED)

### G1 — Atomicity
Execution either:
- completes fully, or
- reverts entirely

No partial state transitions are permitted.

---

### G2 — Determinism
Given:
- identical program bytes
- identical ASP mappings
- identical chain state

Execution outcome MUST be identical.

---

### G3 — No Asset Leakage
For every asset `A`:
- balance_before(A) == balance_after(A)
except where explicitly allowed by the program semantics.

---

### G4 — Flash Loan Conservation
For each flash lender `L`:
- borrowed_amount(L) == repaid_amount(L)

No net debt may remain.

---

### G5 — Nonce Consumption
Each nonce:
- is consumed exactly once
- is consumed before any flash borrow
- cannot be replayed cross-chain

---

## 3. DFA Invariants (LOCKED)

### D1 — Valid State Transitions
Only transitions defined in ORCH-H-DFA.md are permitted.

---

### D2 — RAID / WITHDRAW Symmetry
count(RAID) == count(WITHDRAW)

Violation MUST revert before execution.

---

### D3 — END Finality
END opcode:
- must appear exactly once
- must be the final opcode

---

## 4. Interpreter Invariants (LOCKED)

### I1 — Gas Upper Bound
Logical gas used MUST NOT exceed declared gas limit.

---

### I2 — Opcode Legality
Every opcode byte MUST map to a known instruction.

---

## 5. Guard Invariants (LOCKED)

### C1 — Reentrancy Prohibited
Execution MUST NOT be re-entered during runtime.

---

### C2 — Balance Snapshots
Pre/post balance snapshots MUST match invariant rules.

---

## 6. Proof Strategy (NON-BINDING)

These invariants are designed to be compatible with:
- Scribble annotations
- Certora specs
- SMT-based symbolic execution
- ZK trace commitments (Phase 11)

---

## 7. What This Checkpoint Does NOT Do

- No code execution changes
- No opcode changes
- No semantic changes
- No adapter changes

This checkpoint is **purely formalization**.

