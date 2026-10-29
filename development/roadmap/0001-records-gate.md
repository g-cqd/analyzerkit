---
status: done
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

## Done

`Tests/RepositoryTests` (diary 2026-10-29-03). The test of the rules failed on a stub that found nothing (commit "test: red
— the documentation law as tests"), then passed with the rules. Broken on purpose once against the real records (an ADR
status, a reference to an ADR numbered 0099, which does not exist, a roadmap entry blocked by finished work): all three reported, then restored from a copy. Linux: green in analyzerkit's CI on `553b2e2` (2026-10-29).
