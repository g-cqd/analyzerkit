---
status: in-progress
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
