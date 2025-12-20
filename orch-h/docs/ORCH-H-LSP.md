# ORCH-H Concrete LSP Adapters
Version: 0.6  
Checkpoint: 6  
Status: CORE SECTIONS LOCKED

---

## 1. Adapter Philosophy (LOCKED)

- One adapter per protocol
- Uniform interface (IFlashLender)
- Executor remains protocol-agnostic
- Adapters are thin, auditable, deterministic

---

## 2. Supported Patterns (LOCKED)

- Aave V3-style single-asset flash
- Balancer-style multi-asset flash (wrapped as single calls)

---

## 3. Safety Rules (LOCKED)

- Adapter MUST NOT retain funds post-transaction
- Adapter MUST repay exact principal (+ fee if applicable)
- Adapter MUST revert on callback mismatch

