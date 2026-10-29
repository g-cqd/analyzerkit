---
status: not-started
blocked-by: [0018, 0019, 0020, 0021, 0022]
date: 2026-10-29
---

# 0029 — Benchmarks and budgets for every tool

Scope: ordo-one benchmark packages for fcheck and modeler (arcleak, deadwood and dolly have one); every tool benchmarks
cold and warm scans of a pinned corpus (a snapshot of a g-cqd package, so CI can run it) with thresholds for time and
allocations; a `Scripts/timings.sh` per tool from `research/probes/perf/timings.sh` for the maintastic measurement.

The benchmark packages of arcleak, deadwood and dolly depend on their tool through `url:, branch: "main"`, so they
measure the pushed `main`, never the working tree a change is made in; they move to `path: ".."` (diary 2026-10-29-04). Their
`Package.resolved` had drifted below their own manifest (package-benchmark 1.36 against `from: "1.38.0"`) until 0002.

Red: thresholds set from the measured baseline minus the targeted gain fail before the speed entries (0004, 0007, 0016,
0017, 0024, 0025, 0027) land.

Acceptance: thresholds green; a table of before/after per tool in this repository's diary.
