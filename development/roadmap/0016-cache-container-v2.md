---
status: not-started
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
