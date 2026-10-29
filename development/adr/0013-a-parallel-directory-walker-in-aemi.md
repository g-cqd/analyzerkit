---
status: superseded
superseded-by: ADR-0022
date: 2026-10-29
---

# 0013 — A parallel directory walker, in Aemi's I/O layer

## Context

Discovery is the largest serial cost of every warm run: dolly spends 494 of 670 main-thread samples in
`discoverSwiftFiles`, arcleak about 90 % of its main thread in discovery and the repository-root walk. analyzerkit's
`SourceDiscovery` builds a Foundation `attributesOfItem` dictionary for every entry, `.swift` files included, to learn
whether it is a directory or a link. Other programs walk trees the same way: ask's `ProjectLister` (the `@` picker's
bounded walk with a skip set and a symlink policy) and KittyCode's `SymbolDiscovery`. AemiIO has `PosixFile` and
`RawFileMap` but no directory API.

## Decision

1. The walker lives in Aemi, in a new `AemiFileSystem` target beside `AemiIO` (second consumers exist: ask, KittyCode).
2. It reads entry types without a per-entry stat: `getattrlistbulk` on Darwin (name, object type, device and inode only
   for directories and links), `getdents64`/`readdir` with `d_type` elsewhere, and `fstatat` only when the type is unknown
   or a link must be resolved.
3. It descends with `openat` on directory descriptors (`O_DIRECTORY | O_NOFOLLOW`), so no path is resolved twice and a
   directory swapped for a link during the walk is not followed.
4. It is parallel: a bounded pool of workers (default: active processor count, capped by a descriptor budget) takes
   directories from a work-stealing queue; each worker lists one directory completely.
5. Policies are inputs: names never entered, hidden entries, symlink policy (never, or within the root with a
   device-and-inode visited set), a name predicate, a path predicate evaluated before descending (so `PathFilter` prunes),
   a result limit, cancellation.
6. Results are deterministic: sorted by path at the end, and also available as an `AsyncSequence` of batches so the corpus
   scan reads and parses files while the walk continues.
7. Unreadable directories are reported with their error, not dropped silently.

## Consequences

- `SourceDiscovery` becomes a thin policy over the walker; ask and KittyCode may adopt it.

## Open questions

- `getattrlistbulk` against `readdir` + `d_type` on APFS for source trees; parallel speed-up on one SSD; the descriptor
  budget. Roadmap 0006 probes these on maintastic and on a large checkout before the API is fixed.
