---
status: in-progress
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

## Progress

analyzerkit `bd93a6d` (red `6285968`): `IndexQueries`. It holds a file's definitions and occurrences, a USR's
occurrences by role, `hasOccurrences`, lookup by exact name and by base name (`fetch` finds `fetch(id:)`, not
`fetchAll()`), and `childOf` containers. Every path comes back canonical. Each `Occurrence` keeps IndexStoreDB's
record and reads its fields from it. 5 tests on a fixture store, including the `/private/var` spelling.

The bar, ADR-0025's heavy row (121 common symbols, 108,313 occurrences, maintastic's Xcode store, release, best of
four):

| | time |
| --- | ---: |
| IndexStoreDB `occurrences(ofUSR:)`, paths as recorded | 0.44 s |
| `IndexQueries.occurrences(ofUSR:)`, canonical paths | 0.49–0.50 s (1.10–1.12) |
| IndexStoreDB plus canonicalization as swift-search does it today | 0.68 s |
| `IndexQueries` without canonicalization (a probe) | 0.45 s (1.01) |

The 10% bar is missed by up to 2 points, and the whole difference is canonicalizing 108,313 paths, which callers
pay today at 0.24 s more. Kept as is: canonical paths are this entry's point.

Next: arcleak, deadwood and swift-search read through `IndexQueries`, with byte-equal reports.
