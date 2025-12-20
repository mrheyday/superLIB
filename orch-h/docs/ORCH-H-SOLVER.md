# ORCH-H Solver Tooling
Version: 0.9  
Checkpoint: 9  
Status: CORE SECTIONS LOCKED

---

## 1. Solver Role (LOCKED)

The solver is an **off-chain agent** that:
- receives high-level intent
- compiles intent → ORCH-H bytecode
- simulates execution deterministically
- submits only valid programs on-chain

---

## 2. Compiler Responsibilities (LOCKED)

The compiler MUST:
- emit canonical ORCH-H bytecode
- enforce opcode ordering
- enforce max 6 flash lenders
- bind ASP identifiers, not raw addresses

Any invalid intent MUST fail compilation.

---

## 3. Simulator Responsibilities (LOCKED)

The simulator MUST:
- re-run DFA validation
- re-run opcode interpretation
- compute balance deltas
- detect invariant violations
- estimate logical gas usage

---

## 4. MEV Safety (LOCKED)

Only programs that:
- compile deterministically
- simulate successfully
- match signed commitment

are allowed to be submitted.

---

## 5. Non-Goals

- Pathfinding
- Price discovery
- Optimization heuristics

These belong to solver strategy, not ORCH-H.

