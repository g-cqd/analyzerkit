---
status: not-started
blocked-by: []
date: 2026-10-30
---

# 0054 — `IndexQueries` (P7)

ADR-0027. The queries three tools make of an `IndexStoreSession`, once: the definitions recorded for a file, the
references of a USR (with roles), a symbol's `childOf` container, the symbols named by a base name (a prefix query
filtered on the name before `(`, the fix swift-search made for `fetch(id:)`). Paths come back canonical (the
`/private/var` fix), so callers compare them with `SourcePath` without converting.

Blocked by the index entries of arcleak and deadwood (0023, 0024), which decide what those tools need; extracting
before them would freeze swift-search's shape.

Red: on the index fixtures (`probes/index-fixtures.sh`), each query against swift-search's current answers, then
arcleak's and deadwood's, byte-equal; a function `fetch(id:)` found by `fetch`; a store under `/var` answers with the
canonical spelling. Bar: the heavy row of ADR-0025 (every occurrence of 121 common symbols) within 10% of IndexStoreDB
called directly.
