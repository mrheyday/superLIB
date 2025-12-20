# ORCH-H Meta-Transaction Model (ERC-4337)
Version: 0.8  
Checkpoint: 8  
Status: CORE SECTIONS LOCKED

---

## 1. Purpose (LOCKED)

This checkpoint enables **gasless execution** of ORCH-H programs using
ERC-4337-style meta-transactions.

The ORCH-H bytecode, DFA, interpreter, and execution semantics remain unchanged.

---

## 2. Design Principles (LOCKED)

- ORCH-H programs are executed **only** by the canonical executor
- UserOperation is a **transport wrapper**, not a semantic layer
- Signatures bind:
  - ORCH-H program hash
  - nonce
  - chainId
  - executor address

---

## 3. Meta-Transaction Flow (LOCKED)

1. User signs ORCH-H commitment (Checkpoint 2)
2. Solver wraps commitment into UserOperation
3. Bundler submits UserOperation
4. EntryPoint calls ORCH-H Meta Adapter
5. Adapter validates and forwards to executor

---

## 4. Security Properties (LOCKED)

- No new replay surface
- No change to nonce semantics
- No calldata mutation
- Executor remains single source of truth

---

## 5. Non-Goals

- Account abstraction wallets
- Paymaster logic
- Fee markets

These are explicitly out of scope.

