# ORCH-H Specification
Version: 0.1  
Checkpoint: 1  
Status: CORE SECTIONS LOCKED

---

## 1. Purpose (LOCKED)

ORCH-H is a deterministic, solver-style atomic execution language.

Goals:
- Multi-source flash loan aggregation (≤6)
- Atomic execution
- Post-state enforcement
- MEV resistance (copy, mutation, replay)
- Meta / gasless compatibility

Bytes are law.  
Words are presentation.

---

## 2. Threat Model (LOCKED)

Untrusted:
- Solvers
- Relayers
- Builders

Trusted:
- Signed intent
- Deterministic execution

Prevented:
- Bundle copying
- Route mutation
- Address substitution
- Semantic re-encoding

Accepted:
- Post-execution market MEV

---

## 3. Language Model (LOCKED)

- Alphabet: 256 canonical words
- ASCII, lowercase
- 1 word = 1 byte
- Canonical encoding

Execution consumes bytes only.

---

## 4. Opcode Space (LOCKED)

Opcode byte range:
0x10 – 0x1F

| Byte | Word | Mnemonic | Arity | Description |
|------|------|----------|-------|-------------|
| 0x10 | bela | HOLD | 1 | No-op |
| 0x11 | bele | RAID | 4 | Flash borrow |
| 0x12 | beli | EXEC | 4 | External execution |
| 0x13 | belo | ASSERT | 4 | Post-state invariant |
| 0x14 | belu | WITHDRAW | 4 | Flash repayment |
| 0x15 | bema | FEE | 3 | Optional protocol fee |
| 0x1E | beri | REVERT | 1 | Explicit revert |
| 0x1F | bera | END | 1 | Program end |

Instruction length is fixed.

---

## 5. Deterministic Automaton (LOCKED)

START  
→ RAID* (≤6)  
→ EXEC*  
→ ASSERT*  
→ WITHDRAW* (must match RAID count)  
→ END  

Illegal transitions revert before execution.

---

## 6. Address Space Partitioning (ASP) (LOCKED)

Programs MUST NOT contain raw addresses.

Global byte layout:
0x00–0x0F  Reserved  
0x10–0x1F  Opcodes  
0x20–0x3F  ASP  
0x40–0x7F  Constants / payloads  
0x80–0xFF  Reserved  

ASP domains:
- LSP  0x20–0x27  Flash lenders
- ASPA 0x28–0x2F  Assets
- XSP  0x30–0x37  Execution adapters
- GSP  0x38–0x3F  Guards / utilities

---

## 7. Per-Chain Model (LOCKED)

- Language is chain-global
- ASP mappings are chain-local
- Same byte → different address per chain

Signatures MUST bind:
- chainId
- executor address

---

## 8. Registry Requirements (LOCKED)

- Byte → address only
- Domain checked
- Revert on missing entry
- Immutable during execution
- Executor-bound

---

## 9. Non-Negotiable Rules (LOCKED)

1. Bytes are law
2. No raw addresses
3. No on-chain price reads
4. No dynamic execution
5. Nonce before flash
6. Signature binds exact byte stream

---

## 10. Next Phases (UNLOCKED)

- EIP-712 signing
- Executor contract
- Flash adapter interfaces
- Formal invariants
