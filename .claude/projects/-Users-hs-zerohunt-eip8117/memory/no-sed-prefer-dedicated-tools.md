---
name: no-sed-prefer-dedicated-tools
description: "On this macOS repo, do not use sed — prefer Read/Grep/Edit; if shell text-processing is unavoidable use awk/bash builtins"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: ac6c1d2d-9afa-452b-8c30-1cc383d7e2df
  modified: 2026-07-21T10:58:54.635Z
---

Do not use `sed` in this environment. This is macOS: `sed` is BSD `sed`, not GNU `sed`, and behaves differently (in-place is `-i ''` not `-i`, different flag/regex handling). Beyond portability, the harness guidance already says to avoid `sed`/`awk`/`cat`/`head`/`tail` in Bash and use dedicated tools.

**Why:** In the 2026-07-21 session I used `sed` repeatedly and it bit me — a `s/^/  origin\/$b: /` on branch names containing `/` failed with "bad flag in substitute command" because the slashes collided with sed's `s///` delimiter, garbling the output of a branch-deletion step and making a successful operation look like it failed. BSD-vs-GNU differences and delimiter fragility make `sed` an unreliable default here.

**How to apply:** Read files with the Read tool, search with Grep, make in-place edits with Edit — never `sed`/`cat`/`head`/`tail` for those. If shell text-processing is genuinely unavoidable, prefer **`perl`** (`perl -pe`, `perl -i -pe '…'`) — it ships consistently on macOS, has full PCRE, and lets you pick a delimiter that avoids `/` collisions (`s{…}{…}`, `s|…|…|`); bash parameter expansion also works for simple cases. Never `sed`. Verify the end state with an independent read rather than trusting the command's own chatter. Authoritative project copy: `mev-arbitrum/CLAUDE.md` → "Locked tooling → Shell". See also [[never-guess-verify-ground-truth]].
