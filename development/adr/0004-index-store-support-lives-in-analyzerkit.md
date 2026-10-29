---
status: accepted
date: 2026-10-29
---

# 0004 — Index-store support lives in analyzerkit

## Context

arcleak and deadwood carry diverged forks of the same code lifted from SwiftStaticAnalysis: `IndexStoreReader` (48 %
similar), the fallback manager (38 %), `ProcessExecutor` (36 %), `BinaryTrustChecker` (31 %). The forks disagree on the
trust policy (deadwood refuses a user-owned `Xcode.app`, arcleak accepts it), on unreadable mtimes, and on messages; both
write an `IndexDatabase/` next to whatever path they are given (probes A6, D1, D4).

## Decision

1. A new analyzerkit product, `IndexStoreSupport`, depending on `indexstore-db` on macOS only, holds: store-path
   normalisation (`<DerivedData>`, `Index.noindex`, `DataStore`, `DataStore/vN`, `.build/…/index/store`), discovery through
   `ProjectLayout`, toolchain and dylib resolution with one trust policy (ADR-0014), opening with a database in the tool's
   cache directory (never next to the store), coverage classification, the relative-unit-path guard, and the process
   executor.
2. arcleak and deadwood use it; fcheck and modeler may.
3. It lives in analyzerkit, not in a separate package (owner's decision, 2026-10-29).

## Consequences

- dolly, fcheck and modeler resolve and fetch `indexstore-db` and `swift-lmdb` through analyzerkit, without building them.
  If that cost shows in their CI, the module moves to its own package by a superseding ADR.
- A wrong path is reported as "not an index store" and nothing is created in it.
- Concurrent tools on one database were probed safe (3 concurrent arcleak + deadwood runs, identical results), so the
  database location can be shared between tools: `<cache root>/index/<hash of the store path>`.
