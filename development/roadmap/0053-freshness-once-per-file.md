---
status: not-started
blocked-by: []
date: 2026-10-30
---

# 0053 — Freshness decided once per file in a session (P8)

ADR-0027, ADR-0005. Whether a file's index records are current is a question of its unit and its modification time; an
`IndexStoreSession` answers it once per file and remembers the answer for its lifetime. swift-search asks per match (its
H3: N+1 `isCurrent` calls, each a database lookup and a `stat`). The memo is the session's, so nothing outlives a run.

Red: a session counting its lookups answers 1,000 questions on 10 files with 10 lookups; a file touched after the
session opened is still answered from the memo (documented: a session is a snapshot); a new session sees the change.
