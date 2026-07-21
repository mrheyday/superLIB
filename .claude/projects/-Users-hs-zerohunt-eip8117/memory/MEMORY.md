# Memory Index — mev-arbitrum

Persistent cross-session memory. Each linked file holds one durable fact/rule. Project-scoped rules
and the learnings corpus are **not** duplicated here — they live in the repo (see the map below).

## How I work (feedback)

- [Never guess, verify ground truth](never-guess-verify-ground-truth.md) — verify every fact against files / git / docs before asserting; distinguish "verified" from "expected"; confirm end-state with an independent read after any state change.
- [No sed — prefer dedicated tools; perl on macOS](no-sed-prefer-dedicated-tools.md) — BSD sed (macOS) is unreliable; use Read/Grep/Edit, and `perl` (`perl -pe`) when shell text-processing is unavoidable.

## Where project rules & knowledge live (authoritative, in the repo)

- **Tooling discipline + standing rules** → `mev-arbitrum/CLAUDE.md`
  - "Locked tooling → Shell": no sed / use perl, never-guess-verify
  - "Workflow per change" (steps 1–11): branch → … → commit → post-commit improvement+ml agents → delete branch
  - "Standing session discipline": token-saver each session, automatic git flow, continual agent improvement, periodic prompt review, keep docs current
- **Learnings corpus** → `mev-arbitrum/.learnings/LEARNINGS.md` (`LRN-*`), `ERRORS.md`, `FEATURE_REQUESTS.md`
- **Per-session handoff / state** → `mev-arbitrum/SESSION-MEMORY.md` (read first when resuming)
- **ML over the learnings corpus** → `learnings-ml` CLI at `.agents/skills/self-improvement/ml/` (retrieve / cluster / classify / analytics)
