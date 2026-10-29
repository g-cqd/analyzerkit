---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0004 — `RepositoryRoot.common` probes each directory once

Scope (K4): memoise `.git` lookups per directory for the whole call (and per process), so a corpus of n files in d
distinct directories costs O(d) probes, not O(n × depth). Keep the result byte for byte.

Red: a seam counting existence checks; 1,000 files in 10 directories must do at most 10 + depth checks.

Acceptance: counts met; arcleak, deadwood, dolly and fcheck reports unchanged on their golden corpora.
