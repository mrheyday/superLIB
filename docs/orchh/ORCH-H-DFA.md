# ORCH-H Deterministic Automaton
Version: 0.4  
Checkpoint: 4  
Status: CORE SECTIONS LOCKED

---

## 1. DFA Purpose (LOCKED)

The DFA enforces **semantic correctness** before execution.

No instruction may be executed unless the full program:
- parses correctly
- respects opcode order
- respects flash borrow/repay symmetry

Parsing is done **before any side effects**.

---

## 2. States (LOCKED)

| State | Meaning |
|------|--------|
| START | Program entry |
| RAIDING | Flash borrowing |
| EXECUTING | External calls |
| ASSERTING | Invariant checks |
| REPAYING | Flash repayment |
| END | Program termination |

---

## 3. Transitions (LOCKED)

START → RAIDING  
RAIDING → RAIDING | EXECUTING  
EXECUTING → EXECUTING | ASSERTING  
ASSERTING → ASSERTING | REPAYING  
REPAYING → REPAYING | END  

Any other transition is invalid and MUST revert.

---

## 4. Enforcement Rules (LOCKED)

- MAX 6 RAID instructions
- Number of WITHDRAW == number of RAID
- END must be final byte
- No opcodes after END

---

## 5. Security Properties

- Prevents malformed programs
- Prevents hidden side-effects
- Eliminates semantic MEV

