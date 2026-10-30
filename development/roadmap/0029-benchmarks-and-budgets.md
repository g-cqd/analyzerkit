---
status: not-started
blocked-by: [0018, 0019]
date: 2026-10-29
---

# 0029 — Benchmarks and budgets for every tool

Scope: ordo-one benchmark packages for fcheck and modeler (arcleak, deadwood and dolly have one); every tool benchmarks
cold and warm scans of a pinned corpus (a snapshot of a g-cqd package, so CI can run it) with thresholds for time and
allocations; a `Scripts/timings.sh` per tool from `research/probes/perf/timings.sh` for the maintastic measurement.

The benchmark packages of arcleak, deadwood and dolly depend on their tool through `url:, branch: "main"`, so they
measure the pushed `main`, never the working tree a change is made in; they move to `path: ".."` (diary 2026-10-29-04). Their
`Package.resolved` had drifted below their own manifest (package-benchmark 1.36 against `from: "1.38.0"`) until 0002.

Include ProjectLayout lookup outside a repository with a very large ancestor directory; avoid an uninvalidated global
cache as a shortcut (diary 2026-10-29-11). Measure both first-use discovery and ordinary repository-bound discovery.

Red: thresholds set from the measured baseline minus the targeted gain fail before the speed entries (0004, 0007, 0016,
0017, 0024, 0025, 0027) land.

Acceptance: thresholds green; a table of before/after per tool in this repository's diary.

## swift-search (added 2026-10-30, ADR-0027)

swift-search joins with its own budgets, on a 5,000-file corpus (maintastic's working tree is 2,973 files: take it with a
pinned g-cqd snapshot beside it):

| Run | Budget |
| --- | --- |
| warm `find <name>` (facts cache present) | < 0.2 s wall, < 100 MB peak resident |
| cold `find <name>` (`--no-cache`) | < 1 s wall |
| repeated MCP `search_symbols` in one server | < 50 ms per call after the first |

Its hotspots H1–H12 (swift-search roadmap) are the speed entries that must land before these thresholds can be green:
H3 (0053 here), H5, H7, H8 (AemiJSON's AemiJSONRPC), H10 (0051 here). Measured today only on SwiftStaticAnalysis's 156
files (0.06 s cold, 0.03 s warm; swift-search diary 2026-10-29-01).
