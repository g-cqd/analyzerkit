---
status: not-started
blocked-by: [0018, 0019, 0020, 0021, 0022]
date: 2026-10-29
---

# 0029 — Benchmarks and budgets for every tool

Scope: ordo-one benchmark packages for fcheck and modeler (arcleak, deadwood and dolly have one); every tool benchmarks
cold and warm scans of a pinned corpus (a snapshot of a g-cqd package, so CI can run it) with thresholds for time and
allocations; a `Scripts/timings.sh` per tool from `research/probes/perf/timings.sh` for the maintastic measurement.

Red: thresholds set from the measured baseline minus the targeted gain fail before the speed entries (0004, 0007, 0016,
0017, 0024, 0025, 0027) land.

Acceptance: thresholds green; a table of before/after per tool in this repository's diary.
