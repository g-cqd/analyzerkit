---
status: done
blocked-by: []
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

## Done

deadwood `6c9fc26` (red `aea11b6`).

- **D2.** References from files the index does not cover keep the definitions of the base name they use alive, from
  deadwood's own parse. Production roots leave out those of test files.
- **Advice.** The stale note is one note per class: no unit ("not built by this scheme or not built yet") or changed
  since the build ("re-run the build").
- **One query per file.** The graph build queries each file once, in parallel, into a summary merged in file order.
  Accessor aliases come first and canonical paths are memoised. The store opens once per run, counted by a
  task-local `IndexQueryCounter`.
- **Scaling.** Eight times the files build in well under 24 times the time.
- **D5.** The zero-reference count only runs under `--verbose`.

Measured on maintastic with the Xcode store, release, load 2 to 4: 7.8 → 4.4 s real, and 11.4 → 9.5 s user. With
D2 off, the findings are exactly the 126 of before. D2 removes 36, each kept alive by a name that one of the 34
uncovered files uses, transitively for seven of them. That is ADR-0005 item 4's choice: by name, conservatively.
Common names (`id`, `title`, `displayName`) mean a few uncovered files can hide real dead code; the note says that
their uses count by name.

Interning USRs is 0047's deadwood row; the parallel build already halved the run.
