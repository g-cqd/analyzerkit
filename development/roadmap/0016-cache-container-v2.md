---
status: done
blocked-by: []
date: 2026-10-29
---

# 0016 — Cache container v2

Scope (ADR-0011): `--cache-path` is a directory (a v1 file there is replaced); stat key then content hash with the
racy-clean rule; sharded files rewritten only when changed; memory-mapped with lazy per-entry decode; per-tool budget with
LRU eviction of workspaces then shards; legacy files removed; the index database under the cache root.

Red: a warm hit opens no source file when the stat key matches (counting seam; today every file is opened); a file edited
within the same mtime second is re-hashed; a cache over budget is trimmed; a v1 file at `--cache-path` is replaced; a
corrupt shard is a miss, never a trap.

Acceptance: tests; on maintastic a warm run of each tool after 0018–0022 measured before and after.

## Done

Diary 2026-10-29-22. AemiProtobuf `b11dc91` (pinned to the aemi analyzerkit uses); analyzerkit `1d114e4` red, `701b7b9`
green, then canonicalization `91eced2` (its red just before).

- `CorpusScanner.scan(paths:cache:identity:salt:width:extract:)` with a `CacheLocation` (root, workspace, budget) and a
  `CacheIdentity`; `CacheLocation.defaultRoot(tool:environment:home:)`. The v1 `FactsCache` is gone.
- Stat key (device, inode, size, mtime and ctime in nanoseconds) first, outside a one-second racy window; then the salted
  XXH64. `filesRead` is the counting seam: a warm run whose keys match reads nothing.
- 32 shards per workspace, chosen by directory; AemiProtobuf wire format; memory-mapped (`RawFileMap`), indexed without
  decoding payloads (`readPayloadRange`), a payload decoded only on a hit and copied as is when its shard is rewritten;
  written by rename, so a reader's mapping never changes under it; only changed shards rewritten.
- The salt is part of the shard's header: a guard test that passed against the stub caught a stat-key hit ignoring it.
- Budget per root (512 MiB): least recently used workspaces and index databases, then the current workspace's oldest
  shards. A v1 file at the cache path is replaced; a non-cache file there is left alone and no cache is used; legacy
  `<key>/facts.json` directories go only when the file carries a v1 header.

Measured on maintastic (2,980 files, release, warm file cache, a probe facts type of up to 400 identifiers per file):
cold 171–287 ms; warm 46 ms with no file read, of which canonicalizing 15 ms (25 before `91eced2`), stat 2–3 ms, mapping
and indexing 2 ms, decoding every payload 26–29 ms. Reading and hashing every file alone, the floor of the old design
before its own decoding, is 39–51 ms. Cache 5.9 MB in 32 shards, median 176 KiB, largest 339 KiB.

Ten tests guard behaviour a cache-less stub could not break (no identity, salt, an edit keeping size and mtime, a
cancelled scan, the budget) and passed against it; the rest were red. Acceptance on the tools waits for 0018–0022.
