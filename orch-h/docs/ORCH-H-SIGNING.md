# ORCH-H Program Commitment & Signing
Version: 0.2  
Checkpoint: 2  
Status: CORE SECTIONS LOCKED

---

## 1. Commitment Model (LOCKED)

A solver submits **bytes**, not intent.

Commitment hash:

keccak256(
  chainId,
  executor,
  nonce,
  programBytes
)

Any mutation invalidates the signature.

---

## 2. EIP-712 Typed Data (LOCKED)

### Domain
- name: "ORCH-H"
- version: "0.2"
- chainId: bound at signing
- verifyingContract: executor

### Types

ProgramCommitment:
- uint256 chainId
- address executor
- uint256 nonce
- bytes32 programHash

---

## 3. Nonce Rules (LOCKED)

- Nonce is **user-scoped**
- Consumed **before** any flash loan
- Single-use only
- Replay across chains forbidden

---

## 4. MEV Protection (LOCKED)

- Signature binds exact byte stream
- Executor verifies hash before parsing
- ASP resolved only after verification
- Any deviation reverts pre-execution

---

## 5. Executor Responsibilities (LOCKED)

Executor MUST:
- verify signature
- verify nonce
- enforce DFA
- enforce RAID/WITHDRAW symmetry
- revert before side-effects on failure

