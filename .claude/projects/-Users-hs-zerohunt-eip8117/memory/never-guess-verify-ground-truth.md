---
name: never-guess-verify-ground-truth
description: "Never guess, never assume — verify every fact against ground truth (files, git state, docs) before asserting or acting"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: ac6c1d2d-9afa-452b-8c30-1cc383d7e2df
  modified: 2026-07-21T10:53:56.444Z
---

Never guess and never assume. Before asserting a fact or taking an action, verify it against ground truth — read the actual file, query the actual git/remote state, run the actual command and check its real exit code. Distinguish sharply between "I verified X" and "I expect X"; only state the former as fact. When unsure, check — do not guess. This is also documented as a caveat in [`SESSION-MEMORY.md`](../../../../mev-arbitrum/SESSION-MEMORY.md) ("measured, not guessed"; "always independently verify with raw `git worktree list`") — session rules/handoff live in `SESSION-MEMORY.md`, pointed to from `CLAUDE.md`.

**Why:** In the 2026-07-21 session, every avoidable error came from assuming instead of verifying: (1) reported "Build passed" from `forge build | tail` — assumed the pipe's exit code was forge's, when the build had actually failed; (2) predicted "bytecode identical" for a named-constant refactor — assumed a `constant` compiles identically to its literal, but via_ir emitted 4 different bytes; (3) misread a branch SHA as diverged — assumed from garbled output instead of checking `git ls-remote`; (4) used BSD `sed` assuming GNU behavior. Each was only caught by an independent verification, and each false assertion cost trust.

**How to apply:** Read the source before claiming what it says. After a state-changing command (push, merge, delete, build), confirm the end state with an independent read (`git ls-remote`, `git status`, re-inspect the file) rather than trusting the command's own chatter. Never pipe a command whose pass/fail you care about through a pager (masks the exit code). If a claim can't be verified now, say so explicitly instead of guessing. See also [[no-sed-prefer-dedicated-tools]].
