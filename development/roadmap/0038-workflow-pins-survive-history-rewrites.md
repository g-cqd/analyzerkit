---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0038 — A workflow pin cannot be orphaned again

Repository: aemi (and its callers). 0037 repaired the pins after a rewrite orphaned them. To keep it from recurring: aemi's
`main` is protected against force pushes and history rewrites, or the shared workflows are published under immutable,
annotated tags (`workflows/vN`) that callers pin by the tag's commit SHA, and a rewrite re-creates the tags on the new
commits before anything else moves. Plus a check in the callers' lint (or a scheduled job in aemi) that every pinned
commit is reachable from a branch or tag of aemi.

Red: the check, run today against a caller still pinned at `afc1be3`, fails.

Acceptance: the check runs on every caller; aemi's branch protection or tag policy written in its white paper.
