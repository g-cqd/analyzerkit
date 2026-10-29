---
status: in-progress
blocked-by: []
date: 2026-10-29
---

# 0001 — A test that enforces the documentation law in analyzerkit

Scope: `DocumentationLayout` and `DocumentationLayoutTests` in a `RepositoryTests` target (as AemiProtobuf's and
TerminalKit's): front matter of ADRs (`accepted`, or `superseded` with a successor that names it back) and of roadmap
entries (`status` among `not-started`, `in-progress`, `done`; `blocked-by` naming entries that exist and are not done while
the entry is unfinished); a `date:` on both; one number per file; diary files named `YYYY-MM-DD-NN.md` and ≤ 256 lines; the
white paper ≤ 200 lines; local references (`ADR-NNNN`, `roadmap NNNN`, research `<file>.md`) resolve. The five tools adopt
the layout in 0036.

Red: each rule tested against records that break it on purpose; the rules fail on a stub that finds nothing.

Acceptance: green on this repository's records, on Linux and macOS CI.
