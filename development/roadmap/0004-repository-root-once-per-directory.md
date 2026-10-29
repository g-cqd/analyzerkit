---
status: done
blocked-by: []
date: 2026-10-29
---

# 0004 — `RepositoryRoot.common` probes each directory once

Scope (K4): memoise `.git` lookups per directory for the whole call (and per process), so a corpus of n files in d
distinct directories costs O(d) probes, not O(n × depth). Keep the result byte for byte.

Red: a seam counting existence checks; 1,000 files in 10 directories must do at most 10 + depth checks.

Acceptance: counts met; arcleak, deadwood, dolly and fcheck reports unchanged on their golden corpora.

## Done

Diary 2026-10-29-07. `RepositoryRoot` had no tests: six characterization tests on real trees came first (green on the old
code), then the counting seam and its red test (3,000 probes for 1,000 files in 10 directories), then the per-call memo
(≤ 13). Per call, not per process: a process-wide memo would need a lock and could go stale when a repository is created
during a long run, and one call already covers a whole corpus. dolly on maintastic with this tree: byte-identical report;
warm 0.93 → 0.83 s (median of five, interleaved).
