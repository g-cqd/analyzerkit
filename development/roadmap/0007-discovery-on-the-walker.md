---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0007 — `SourceDiscovery` on the walker, streaming into the scan

Scope (K5): `SourceDiscovery` becomes a policy over `AemiFileSystem.DirectoryWalk` (aemi ADR 0017) (skip `.build`, `.git`, `DerivedData`, `.swiftpm`,
`checkouts`, hidden entries; `PathFilter` pruning); `CorpusScanner` consumes the batch sequence so reading and parsing start
before the walk ends.

Red: the counting seam (no stat per regular file); identical file lists to today's on golden trees.

Acceptance: dolly's and arcleak's main-thread discovery share drops on maintastic (measured before and after, median of
five, quiet machine).

Also: `ProjectLayout`'s ancestor lookup lists each ancestor with `FileManager.contentsOfDirectory`, 22.9 s on a
267,000-entry directory against 134 ms with `readdir` (aemi's diary 2026-10-29-02); its container check moves onto the
walker's listing too.
