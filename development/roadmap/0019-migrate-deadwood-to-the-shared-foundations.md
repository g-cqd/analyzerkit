---
status: done
blocked-by: []
date: 2026-10-29
---

# 0019 — Migrate deadwood to the shared foundations (wave 1)

Repository: g-cqd/deadwood. Scope: replace the tool's own discovery, path filter, report formatter, baseline, path
presentation, suppression, command-line options and facts cache with analyzerkit's (ADR-0016); read
`.swift-analyzers.json`; keep the old flag spellings as aliases. Its `IndexStore/` directory moves onto `IndexStoreSupport`, keeping today's behaviour; its `GlobMatcher`, `SafeRegex` and `RegexCache` are deleted (ADR-0008). Its cache now fits (0016, 0017), so maintastic can drop `--no-cache`.

Red: golden reports (xcode, JSON, SARIF, baseline) recorded from the current release on the tool's fixture corpus and on a
pinned snapshot of a g-cqd package; the migrated tool must match them byte for byte apart from added keys. The shared
`--help` and exit-code goldens of 0013 fail until the migration lands.

Acceptance: goldens green; the tool's suite green; its own copies of the replaced files deleted; timings on maintastic before
and after in the tool's diary.

From 0010: analyzerkit pins indexstore-db at `0390867` (upstream `main`); deadwood's `64aa0b2` must move with the
analyzerkit bump. Its `ProcessExecutor` and `BinaryTrustChecker` forks go; `IndexStoreSession` replaces the reader's
opening (database under the cache root, not beside the store).
`ToolchainResolution.resolve()` is async since 0010 (it runs `xcode-select` and `xcrun` through `BoundedProcess`).

From 0016: `CorpusScanner.scan` takes `cache: CacheLocation` (root from `--cache-path` or `CacheLocation.defaultRoot`, the
workspace, the budget) and a `CacheIdentity`; `FactsCache` is gone, so the tool's own cache moves onto the container.

From 0043: `ProjectClassification.load(layout)` once per run, then `classify(path, tree:)` per file, replaces the
`TestConventions` and `GeneratedCode` calls in `DeadwoodCore` `Engine/TestScopeClassifier.swift` (deleted with its glob), `Engine/CorpusContext.swift`, `Engine/UnusedCodeConfiguration.swift`, `Engine/RootDetection.swift`, `Engine/Reachability/DependencyExtractor.swift`, `Cache/CachedFileFacts.swift`, `Facts/StaticAnalyzer.swift`, `Facts/Models/AnalysisResult.swift`. Its `issues(for:)` (`project-unknown`, `project-unclaimed`)
become run notes. 0043's acceptance that every tool selects the same regions for the same fixture and configuration is
checked here, by a shared fixture each migration runs.

## Done

deadwood on analyzerkit `4585088`, in two steps, each red first.

- **Step A** (red `424d10b`, green `c388f82`).
  - **Options.** `analyze` takes the six shared option groups, with `--production` and `--minimum-confidence` after
    them. `--include`/`--exclude` and `--experimental-embedding-confidence` are deprecated aliases that print a note.
    `--define` says it has no effect, since deadwood reads the code of every clause. `--exclude-path` scopes the
    report, never the corpus, as `exclude` does. `--rules`, `--quiet` and `--timings` are new. `NewFindings` gave
    way to `NewSince`.
  - **Cache.** `FactsCache` is gone; `CorpusScanner` stores `ExtractedArtifacts`, salted by the whole configuration.
    A skipped file is cached as such, with the release's wording.
  - **Regions.** The content region is cached and the project region joined every run. Production mode's test files
    are the test region now, not `Tests/` or `*Tests.swift` by path; `testsGlob` still overrides, read through
    `PathFilter`.
  - **Deleted.** `GlobMatcher`, `SafeRegex`, `RegexCache`, and the path, name and ignore patterns nothing ever set.
- **Step B** (red `ca4eb2a`, green `9e09cdd`).
  - **Stores.** They open through `IndexStoreSession`, with the database under the cache root, and the session's
    coverage gives the stale files, whose findings are dropped as before. The bridge queries the session's reader
    instead of opening a second one, so the store opens once per run (part of 0024).
  - **Locations.** Stores are found and named through `IndexStoreLocation`: a build directory resolves to its store,
    and a store under a target triple is found.
  - **Auto-build.** `--index-store-build` runs through `BoundedProcess`.
  - **Deleted forks.** `ProcessExecutor`, the trust shim, `IndexStorePathFinder` and `IndexStoreStatus` are gone.
  - **One behaviour change.** A store that indexes none of the analyzed files as they are now is refused with a note
    before any lookup. Before, it was opened and every finding was dropped as stale: a silent empty report.

Findings are byte-equal to the release on analyzerkit's sources and maintastic, in xcode, JSON and SARIF, with and
without the index store; the goldens are unchanged. The only additions are maintastic's `project-unclaimed` note (two
Dangerfiles, as dolly reports them) and the store's canonical path in the index note. 389 tests pass, with a 585 MB
peak.

Timings on maintastic, debug build, under a load of 9 to 11:

- **Without a cache:** 34 to 35 s, against 30 to 34 s for the release, with about 5% more CPU. Detection is 18 s,
  scanning 16 s.
- **Cache:** the release's cache never fit its 64 MiB cap on this corpus, so it never hit. The new one is 97 MB in
  shards, and a warm run skips the scan: 17.7 s.
