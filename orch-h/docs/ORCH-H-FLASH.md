# ORCH-H Flash Loan Model
Version: 0.3  
Checkpoint: 3  
Status: CORE SECTIONS LOCKED

---

## 1. Flash Loan Philosophy (LOCKED)

Flash loans are **mechanical liquidity**, not strategy.

Rules:
- Maximum of 6 lenders per program
- All borrows must be repaid in the same transaction
- Order of repayment must match order of borrowing
- No partial repayment
- Any mismatch reverts entire execution

---

## 2. LSP Adapter Interface (LOCKED)

Each lender is abstracted behind a uniform interface.

The executor:
- does not know protocol specifics
- only enforces balance deltas

---

## 3. Atomic Execution Guarantee (LOCKED)

Borrow → Execute → Assert → Repay is a single atomic state transition.

If any step fails:
- all flash loans revert
- no external side effects persist

---

## 4. MEV Safety (LOCKED)

- Borrow amounts are fixed at signing time
- No on-chain price reads
- No adaptive routing
- No conditional branching on market state

---

## 5. Executor Responsibilities (LOCKED)

Executor MUST:
- enforce max 6 LSPs
- track borrowed amounts per LSP
- verify full repayment
- revert on any mismatch

