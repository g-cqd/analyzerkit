---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0026 — modeler: interleavings on the control-flow graph (wave 2)

Repository: g-cqd/modeler. Scope: reentrancy and lock-gap analysis as a dataflow over `ControlFlowGraph` (state: checked,
claimed and stale members); a write before the suspension is a claim; a post-suspension write after a claim is reported, as
a new kind, only when another method of the type writes the member (M1); loop-carried staleness (M2); no pairing across
exclusive branches (M3); README corrected (M4); its cache through 0016 (M5).

Red: `ModelerProbes.swift` as tests, with the expected results in its header.

Acceptance: tests; TLA+ emission unchanged on its golden files; findings on the g-cqd packages before and after in the
release note.
