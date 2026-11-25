---
status: accepted
date: 2026-10-29
---

# 0002 — Evidence first, red tests first

## Context

The first review of the index-store reports made claims from reading code. Probing them (diary 2026-10-29-01) confirmed
most, made three worse than stated (A4, A6, D4), refuted two (A3b, A7's corruption) and retracted one (the `/tmp` symlink).
A plan built on the unprobed version would have fixed things that were not broken and missed what was.

## Decision

1. Every item of the roadmap starts as a failing test committed alone, failing for the reason the item states; the fix
   follows in its own commit; refactoring comes after green.
2. The probes recorded in `research/probes/` are the seeds of those tests. A claim without a probe is written as an open
   question.
3. Performance items are red too: an operation count through a seam, a scaling ratio, a size budget, or a benchmark
   threshold that the current code fails. No test gates on wall-clock time alone.
4. Surface items are red as golden tests (help, JSON envelope, exit codes) that the current tools fail.

## Consequences

- A red commit on `main` is expected and allowed only when the next commit makes it green; CI runs per pull request on
  the final commit, and the red commit is shown failing in the pull request description.
- Index fixtures need a toolchain whose `libIndexStore.dylib` matches the `swiftc` that builds them; such tests are
  `.enabled(if:)` and run on macOS CI, not skipped by `return`.
