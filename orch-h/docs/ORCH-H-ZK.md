# ORCH-H ZK Trace Commitments
Version: 1.0  
Checkpoint: 10  
Status: CORE SECTIONS LOCKED

---

## 1. Purpose (LOCKED)

ZK trace commitments allow an executor or solver to:
- commit to an **exact ORCH-H execution trace**
- prove that execution followed the committed trace
- prevent post-hoc trace manipulation by builders or relayers

This checkpoint defines **structure only**, not proofs.

---

## 2. Trace Model (LOCKED)

An ORCH-H execution trace is an ordered list of steps.

Each step records:

- program counter (pc)
- opcode
- logical gas before
- logical gas after
- ASP domain used (if any)

No dynamic memory, jumps, or branching are allowed.

---

## 3. Trace Encoding (LOCKED)

Each trace step is encoded as:

keccak256(
  pc ||
  opcode ||
  gas_before ||
  gas_after ||
  asp_key
)

All fields are fixed-width.

---

## 4. Trace Commitment (LOCKED)

The full trace commitment is:

trace_root = keccak256(
  step_hash_0 ||
  step_hash_1 ||
  ... ||
  step_hash_n
)

This value MAY be:
- signed off-chain
- included in calldata
- used as a public input to a ZK proof

---

## 5. Binding Rules (LOCKED)

The trace MUST be bound to:
- program hash
- chainId
- executor address

A trace is invalid if any binding changes.

---

## 6. ZK Compatibility (LOCKED)

The model is compatible with:
- zkSNARKs
- zkSTARKs
- recursive proofs

No elliptic curve assumptions are made here.

---

## 7. Non-Goals

- No verifier contract
- No proving system selection
- No recursion logic

Those are deferred by design.
