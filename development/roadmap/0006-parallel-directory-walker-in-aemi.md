---
status: done
blocked-by: []
date: 2026-10-29
---

# 0006 — A parallel directory walker in Aemi (`AemiFileSystem`)

Repository: aemi. Scope (ADR-0022, aemi ADR 0017): probe first, then build.

Probes, recorded in aemi's diary before any API is fixed: (1) `getattrlistbulk` against `readdir` + `d_type` against
`FileManager.contentsOfDirectory` + `attributesOfItem`, single-threaded, on maintastic and on a large checkout
(swift-syntax's), plus a shallow directory with hundreds of thousands of entries (ProjectLayout's no-repository
ancestor lookup, diary 2026-10-29-11); (2) parallel speed-up with 1, 2, 4, 8 workers on one SSD; (3) descriptor use per worker.

Build: `openat`-based descent, work-stealing over directories, policies (skip names, hidden, symlinks never or within the
root with a device-and-inode visited set, name and path predicates evaluated before descending, limit, cancellation),
deterministic sorted result and an `AsyncSequence` of batches, unreadable directories reported. Darwin and Linux.

Red: a counting seam proves no stat per regular file; a link cycle terminates; a directory replaced by a link mid-walk is
not followed; results equal `FileManager`'s on a fixture tree.

Acceptance: the probes' numbers in the diary; the tests; a benchmark with a threshold.

## Progress

Probes done and recorded in aemi's diary 2026-10-29-02 (probe `Benchmarks/DirectoryWalk/walk-probe.swift`): readdir with
`d_type` beats `getattrlistbulk` cold and on huge directories; four workers is the knee; queued directories outnumber the
default descriptor limit, so the queue holds root-relative paths opened with `O_NOFOLLOW_ANY`. ADR-0022 supersedes ADR-0013
on those two points; aemi ADR 0017 fixes the design. Next: the walker, red first.

## Done

Diary 2026-10-29-18; aemi's diary 2026-10-29-02 holds the numbers. aemi `cfd705a` (probe, ADR 0017), `93bc772` red,
`2a99b3e` green: `AemiFileSystem.DirectoryWalk`, built in a separate worktree while other work was under way in aemi's main
checkout. Ten tests: equal to `FileManager` under the same policy in 1–8 workers; no stat per regular file and only the
walked directories opened (the counting seam); pruning before entering; a directory swapped for a link mid-walk refused
(ELOOP); unreadable directories reported; limit, cancellation, batches. 30 repeated runs and ThreadSanitizer clean.

Changed while writing the tests (aemi ADR 0017 item 4, amended before any consumer): links are never descended; under
`withinRoot` a link into the root is left to its target, reached at its own path. A visited set by device and inode would
have made a parallel walk's result depend on which spelling a worker reached first.

The threshold is the operation count (zero stats per regular file, descriptors at most workers + 1), as the white paper
gates on counts, not wall time. Benchmark `directoryWalk/*` in aemi's suite, p50 on a generated tree: 45 ms with a stat per
entry, 7.1 ms on one worker, 4.2 ms on four.

Not done here: the Linux path (component-by-component `openat` with `O_NOFOLLOW`) is written but neither compiled nor run;
the end-of-train CI pass covers it.
