---
status: done
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

## Done

Diary 2026-10-29-21. Three steps, each red then green: `f662a64`/`4831ed6` (locating and coverage), `82ec98e`/`8d694f9`
(the session), `874bfc1`/`3b9be83` (the executor), then a read-only-store guard.

- `IndexStoreLocation.resolve`: a store given as itself, its `vN`, `Index.noindex`, a DerivedData build root, a SwiftPM
  `.build` or configuration (through its link) resolves to the store root; anything else is refused with what to pass,
  and nothing is created (A6/D1 as tests, on hand-made and compiler-written stores). `discover` through `ProjectLayout`;
  `databaseDirectory` = `<cacheRoot>/index/<XXH64 of the canonical store path>`.
- `IndexCoverage`: `indexed`, `notIndexed`, `changedSinceBuild`, `unreadable`; the no-file-indexed gate; `skippedFiles`;
  four note codes (`index-not-used`, `index-changed-since-build`, `index-not-indexed`, `index-unreadable`).
- `IndexStoreSession.open`: resolves, checks the library against the trust policy, opens IndexStoreDB with its database
  under the cache root, classifies, and hands out the database only when some file is indexed, so a store with relative
  unit paths is never queried. Tests compile real stores with `swiftc`: three depths, one database, nothing written
  outside the cache root; a relative-path store not usable; a never-compiled and an edited file classified apart; a
  read-only store opens (written after the implementation, as a guard; never red).
- `BoundedProcess`: deadline (SIGTERM, then SIGKILL after 2 s), output cap with the pipes drained, the forks' environment
  allow-list, absolute executables only, cancellation; `ToolchainResolution.systemProbe` runs through it.
- indexstore-db pinned at upstream `main` `0390867` (the tools' `64aa0b2` is on neither `main` nor `release/6.3`; `main`
  adds parallel record reads). arcleak and deadwood move to it when they adopt (0018, 0019).

Not done here: the compiler-identity note of ADR-0014 item 3 (IndexStoreDB does not expose a unit's provider; 0048).
Acceptance on macOS CI waits for the end-of-train CI pass.
