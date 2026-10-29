---
status: not-started
blocked-by: [0018]
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
