---
status: done
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

## Done

modeler `0efc718` (red `4a6eced`).

- **The graph in the facts:** each body's facts carry its `ControlFlowGraph` as successor lists
  (`MethodFacts.flow`), and each effect the nodes it happens in (`Effect.nodes`). An effect in a `defer` belongs to
  one node per exit. Reentrancy and lock gaps are dataflows over that graph (`FlowSolver`, entry states, 64 visits
  per node). Facts without a graph fall back to source order.
- **M1:** a write after the check and before the `await` claims the member. A write after the `await` is reported
  as the new kind `claimedAwait` (rule `reentrancy`) only when another method of the type writes the member; the
  finding names those methods and the claim's line.
- **M2** carries a check and an `await` through the loop's back edge. **M3** pairs only on one path, for awaits and
  for lock scopes.
- **M4:** the README's limits and shared-code paragraphs are corrected.
- **M5** was already in place: the facts load through `CorpusScanner` (0016).

Acceptance:

- 85 tests pass.
- `modeler facts` leaves the graph out, so every report golden and the TLA+ goldens are byte-equal.
- g-cqd packages: no change.
- maintastic `check`: 28 findings before, 29 after; the release note list is in the diary of 2026-10-30.
- CPU: 1.11 s user before, 1.17 s after (release, `--no-cache`).
