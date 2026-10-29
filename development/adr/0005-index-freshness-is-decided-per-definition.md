---
status: accepted
date: 2026-10-29
---

# 0005 — Index freshness is decided per definition, not per run

## Context

arcleak drops the index for the whole run when any analyzed file has no unit or a newer mtime than its unit: on maintastic
62 of 2,830 files, so the index is never used (A1), after a 9.4 s, 128 MB database import (A1′). The arcleak report
proposed a per-analyzed-file decision. Probing showed the wrong file is checked: arcleak asks the index about types the
corpus does not declare, so what must be fresh is the file that *declares* the answer. After `Plugin` became a struct in
another file, arcleak said "index store active" and reported an error-severity cycle from the stale record (A4). It also
asked the index about types the corpus declares as structs (A2) and took an arbitrary one of two same-named types (A3).

deadwood is the mirror case: references that live only in unindexed files are invisible, so a declaration used only by an
unbuilt test is reported dead (D2).

## Decision

1. Coverage is classified per file: `indexed`, `notIndexed` (no unit), `changedSinceBuild` (newer than its unit),
   `unreadable`. Reports count and list them apart (ADR-0017 `skippedFiles`).
2. The run-wide gate keeps one job: when no analyzed file is indexed, the index is not used ("the store does not describe
   these files; wrong path or wrong build"), which also guards against stores with relative unit paths.
3. arcleak: a name declared anywhere in the corpus is never looked up; a lookup collects every type-kind definition of the
   name, and returns nothing when they disagree or when the declaring file is not `indexed`; it never infers class-ness
   from a kind whose declaring file no longer contains the type.
4. deadwood: declarations in non-indexed files keep today's treatment (not judged); references *from* non-indexed files
   are added to the index graph by name, conservatively; the note's advice depends on the class ("not built by this
   scheme" against "rebuild").

## Consequences

- With the index, arcleak finds more cross-module facts on real projects instead of none; deadwood loses the false
  positives of D2.
- Behaviour changes, so these land in release wave 2 (ADR-0015).
