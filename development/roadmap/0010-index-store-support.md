---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0010 — `IndexStoreSupport` in analyzerkit

Scope (ADR-0004, ADR-0005 items 1–2): path normalisation (`<DerivedData>`, `Index.noindex`, `DataStore`, `DataStore/vN`,
`.build/…/index/store`); discovery through `ProjectLayout`; opening with the database under the cache root
(`index/<hash>`), never next to the store, read-only stores supported; coverage classes `indexed`, `notIndexed`,
`changedSinceBuild`, `unreadable`; the "no analyzed file indexed" gate that also covers relative-unit-path stores; the
process executor; one wording for the notes. The product and toolchain/trust policy already exist from 0009; extend
them rather than introduce another resolver. Replace 0009's narrow synchronous system probes with the shared bounded
executor (including timeouts and output limits), and carry compiler/toolchain mismatch notes when unit metadata provides
the compiler identity (ADR-0014 item 3).

Red: `research/probes/index-fixtures.sh` A6/D1 as tests (three depths of one store resolve to it, nothing is created
anywhere else, a wrong path says "not an index store"); a store with relative unit paths is refused before any symbol query;
a fixture with one never-compiled and one edited file classifies them apart.

Acceptance: the tests on macOS CI (`.enabled(if:)` on a matching toolchain); no `IndexDatabase/` created outside the cache
root in any test.
