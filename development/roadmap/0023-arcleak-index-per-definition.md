---
status: done
blocked-by: []
date: 2026-10-29
---

# 0023 — arcleak: the index decided per definition (wave 2)

Repository: g-cqd/arcleak. Scope (ADR-0005 item 3): names declared anywhere in the corpus are never looked up (A2); a lookup
gathers every type-kind definition and answers nothing when they disagree (A3) or when the declaring file is not `indexed`
(A4); no class-ness from the kind alone when the declaring file no longer declares the type; the run-wide gate only for "no
analyzed file indexed" (A1); the coverage check runs before the database import where the store allows it (A1′); notes and
`skippedFiles` (A8); the backend test `.enabled(if:)` (A9); names and graph tables on `AemiInterner` (0015): type and member names interned at extraction,
the ownership graph keyed by `Symbol`, text resolved only to print a finding (0047).

Red: `ArcleakFakeIndexProbe.swift` (A2) and `index-fixtures.sh` A1, A3, A4 as tests.

Acceptance: probes give the expected results; on maintastic the note reads "index active for N of M files; K not in the
index, J changed since the build" and the run uses the index.

## Done

arcleak `8e2c66c` (red `be91dfe`): ADR-0005 item 3, as tests on fixture stores built with `swiftc`.

- **A2** was wave 0's (`CorpusFirstIndex`): a name the corpus declares is never looked up.
- **A1.** The run-wide gate only drops the index when no analyzed file is indexed; otherwise the note reads "index
  active for N of M files; K not in the index, J changed since the build".
- **A3.** A lookup gathers every type definition of the name, sorted. Kinds that disagree answer nothing, and several
  classes of one name answer "a class" with no edges.
- **A4.** A definition whose declaring Swift file is not current (`IndexFreshness`) is not used, even when the file
  still declares the type.
- **A8.** The coverage notes and the uncovered files are in the JSON report.
- **A9.** The backend test is `.enabled(if:)` and asserts every step.

On maintastic with the Xcode store, the note reads "index active for 2809 of 2838 files; 11 not in the index, 18
changed since the build". The index is used where the run-wide gate dropped it before, and the findings are the same
three.

Moved out of this entry:

- A1′ (the coverage check before the database import) needs a check analyzerkit does not have: 0060.
- Interning names and the ownership graph is 0047's arcleak row, which has its own gate (findings identical, graph
  build faster).
