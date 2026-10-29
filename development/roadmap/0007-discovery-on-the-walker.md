---
status: not-started
blocked-by: [0006]
date: 2026-10-29
---

# 0007 — `SourceDiscovery` on the walker, streaming into the scan

Scope (K5): `SourceDiscovery` becomes a policy over `AemiFileSystem` (skip `.build`, `.git`, `DerivedData`, `.swiftpm`,
`checkouts`, hidden entries; `PathFilter` pruning); `CorpusScanner` consumes the batch sequence so reading and parsing start
before the walk ends.

Red: the counting seam (no stat per regular file); identical file lists to today's on golden trees.

Acceptance: dolly's and arcleak's main-thread discovery share drops on maintastic (measured before and after, median of
five, quiet machine).
