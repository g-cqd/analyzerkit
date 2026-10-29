---
status: accepted
date: 2026-10-29
supersedes: ADR-0013
---

# 0022 — The walker reads directory records, not inodes

## Context

ADR-0013 put a parallel directory walker in Aemi and chose `getattrlistbulk` on Darwin and descent through parent
descriptors, leaving both to be measured (roadmap 0006). Measured (aemi's diary 2026-10-29-02): `getattrlistbulk` reads
every entry's inode, so it is slower than `readdir` with `d_type` cold (130 against 93 ms on maintastic) and 150 times
slower on a directory larger than the vnode cache (20.9 s against 134 ms on the 267,000-entry temporary directory, the one
that stalled the configuration lookup of roadmap 0014). A parallel walk queues up to 440 of maintastic's directories,
more than the 256 descriptors launchd allows a process by default, so descriptors cannot stand for queued directories.

## Decision

As ADR-0013, with its items 2 and 3 replaced by aemi's ADR 0017: `readdir` with `d_type` everywhere, `fstatat` only for an
unknown type, a link to resolve or a directory identity; every directory opened relative to the root with
`O_NOFOLLOW_ANY` (on Linux `openat2` with `RESOLVE_NO_SYMLINKS`), the queue holding relative paths, one descriptor per
worker; four workers by default, the measured knee. The rest stands: the walker lives in Aemi's I/O layer
(`AemiFileSystem`), takes its policies as inputs, reports unreadable directories, and returns a sorted result and an
`AsyncSequence` of batches.

## Consequences

- `SourceDiscovery` on the walker (roadmap 0007) replaces 7,530 `attributesOfItem` calls on maintastic by none: 207 ms
  to about 11 ms warm, 325 to about 36 ms cold, measured with the probe's methods, not the walker itself.
