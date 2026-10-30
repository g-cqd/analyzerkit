---
status: done
blocked-by: []
date: 2026-10-30
---

# 0053 — Freshness decided once per file in a session (P8)

ADR-0027, ADR-0005. Whether a file's index records are current is a question of its unit and its modification time; an
`IndexStoreSession` answers it once per file and remembers the answer for its lifetime. swift-search asks per match (its
H3: N+1 `isCurrent` calls, each a database lookup and a `stat`). The memo is the session's, so nothing outlives a run.

Red: a session counting its lookups answers 1,000 questions on 10 files with 10 lookups; a file touched after the
session opened is still answered from the memo (documented: a session is a snapshot); a new session sees the change.

## Done

`IndexFreshness` (platform-independent, so it is tested without a store): seeded from the coverage made when the store
opened, so analyzed files cost no lookup; any other file costs one unit lookup and one `stat`, then is remembered under a
`Mutex` for the session's life. Lookups run outside the lock; two first questions about one file may both look it up and
the first answer stored wins. `IndexStoreSession.freshness` holds one (IndexStoreDB is wrapped `@unchecked Sendable`, as
the session already documents its own thread safety). 5 tests on counting closures (1,000 questions on 10 files: 10
lookups; a snapshot keeps its answer, a new one sees the edit; 1,000 concurrent questions agree), red at `b21247e`, and
one on a real store (analyzed, outside and never-compiled files). swift-search drops its per-call memo for it in its 0006.
