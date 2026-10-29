---
status: not-started
blocked-by: [0019]
date: 2026-10-29
---

# 0024 — deadwood: index references from unindexed files, and an index path that is fast

Repository: g-cqd/deadwood. Scope: references from `notIndexed` and `changedSinceBuild` files added by name as conservative
edges (D2); advice per coverage class; one store open per run; one `symbolOccurrences(inFilePath:)` pass per file, in
parallel; `canonicalPath` memoised per path; the zero-reference pass (D5) removed or only under `--verbose`; USR tables on
`AemiInterner` (0015): every USR interned once as it is read, per-file tables merged with `Interner.merge`, the
declaration and reference maps keyed by `Symbol` (0047). The probe measured 102 against 17 ms on maintastic's USR stream.

Red: `index-fixtures.sh` D2 as a test (`helper()` not reported); a counting seam for store opens (1) and per-file
occurrence queries (1 per file); a scaling test of the graph build on a synthetic store.

Acceptance: tests; maintastic index run measured before (23.8 s under load) and after on a quiet machine, same findings
apart from D2.
