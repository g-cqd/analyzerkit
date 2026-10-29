---
status: accepted
date: 2026-10-29
---

# 0011 — Cache container v2: stat key first, content hash second, sharded, mapped, bounded

## Context

Every warm run still opens and reads every file to fingerprint it (`__open` is the top self symbol of fcheck's warm run;
`read`, `open`, `getattrlist` and `lstat` together cost arcleak about five times its parse time), then decodes the whole
cache before the first hit. Caches are never evicted: 226 MB in `~/Library/Caches/deadwood` (including a 169 MB legacy file
from July), 140 MB for arcleak, 62 MB for dolly. `--cache-path` names a file; maintastic passes `<dir>/<tool>/facts`.

## Decision

1. `--cache-path` names a directory, the tool's cache root. A regular file found at that path (a v1 cache) is removed and
   replaced by the directory; v1 caches are never read.
2. Entries are keyed by canonical path and validated in two steps: a stat key (device, inode, size, mtime in nanoseconds,
   ctime) and, only when the stat key differs, a content hash (XXH64, salted with what the facts depend on). An entry whose
   mtime is not older than the cache's write time is always re-hashed (git's racy-clean rule).
3. The cache is sharded by the hash of the file's directory into a fixed number of files; a run rewrites only the shards
   it changed. Shards are memory-mapped (AemiIO `RawFileMap`) and an entry's payload is decoded only on a hit.
4. A total budget per tool (default 512 MiB, `cache.maximumBytes`) is enforced by removing the least recently used
   workspaces, then the least recently used shards. Legacy files and directories of older layouts are removed on first run.
5. The index-store database lives under the cache root too (`index/<hash of store path>`), shared by every tool that uses
   the same root (ADR-0004).

## Consequences

- maintastic's `--cache-path ~/Desktop/analyzer-cache/<tool>/facts` keeps working: `facts` becomes a directory.
- A warm hit opens no source file when the stat key matches; a test counts opens through a seam.

## Open questions

- Shard count and budget defaults (to be measured on maintastic and on the g-cqd packages).
- Whether ctime is reliable enough on the CI file systems maintastic uses (self-hosted macOS runners).
