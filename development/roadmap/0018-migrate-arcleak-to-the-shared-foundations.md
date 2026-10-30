---
status: done
blocked-by: []
date: 2026-10-29
---

# 0018 — Migrate arcleak to the shared foundations (wave 1)

Repository: g-cqd/arcleak. Scope: replace the tool's own discovery, path filter, report formatter, baseline, path
presentation, suppression, command-line options and facts cache with analyzerkit's (ADR-0016); read
`.swift-analyzers.json`; keep the old flag spellings as aliases. Its `IndexStore/` directory moves onto `IndexStoreSupport` (0010) with today's run-wide behaviour kept, so findings do not change in wave 1. `IndexStoreLocator` (unused outside tests) is deleted.

Red: golden reports (xcode, JSON, SARIF, baseline) recorded from the current release on the tool's fixture corpus and on a
pinned snapshot of a g-cqd package; the migrated tool must match them byte for byte apart from added keys. The shared
`--help` and exit-code goldens of 0013 fail until the migration lands.

Acceptance: goldens green; the tool's suite green; its own copies of the replaced files deleted; timings on maintastic before
and after in the tool's diary.

From 0010: analyzerkit pins indexstore-db at `0390867` (upstream `main`); arcleak's `64aa0b2` must move with the
analyzerkit bump. `IndexStorePathFinder` skips `.build/out` as a store of relative unit paths; on Swift 6.4 Swift Build
writes absolute ones there (checked on analyzerkit's own build, diary 2026-10-29-21), and `IndexStoreSession` refuses a
relative store by coverage anyway, so the shared discovery includes it.
`ToolchainResolution.resolve()` is async since 0010 (it runs `xcode-select` and `xcrun` through `BoundedProcess`).

From 0016: `CorpusScanner.scan` takes `cache: CacheLocation` (root from `--cache-path` or `CacheLocation.defaultRoot`, the
workspace, the budget) and a `CacheIdentity`; `FactsCache` is gone, so the tool's own cache moves onto the container.

From 0043: `ProjectClassification.load(layout)` once per run, then `classify(path, tree:)` per file, replaces the
`TestConventions` and `GeneratedCode` calls in `ArcLeakCore` `Facts/RegionSpanFact.swift`, `Facts/FileFacts.swift`, `Extraction/FactsExtraction.swift`. Its `issues(for:)` (`project-unknown`, `project-unclaimed`)
become run notes. 0043's acceptance that every tool selects the same regions for the same fixture and configuration is
checked here, by a shared fixture each migration runs.

## Done

arcleak on analyzerkit `4585088`, in two steps, each red first.

- **Step A** (red `7af94d7`, green `51a03ca`).
  - **Options.** `analyze` takes the six shared option groups. `--include`/`--exclude` are deprecated aliases that
    print a note. `--exclude-path`, `--rules`, `--report-new-since` (`NewSince`), `--quiet`, `--verbose` and
    `--timings` are new.
  - **Cache.** `FactsCache` is gone; `CorpusScanner` stores `ExtractedFacts` (the facts, or why the file was not
    analysed), salted by the defines, contracts and platforms. The cache keeps the content region; the project
    region is joined every run, and `project-unknown`/`project-unclaimed` are run notes.
  - **Byte equality.** `String(validating:)` keeps a byte-order mark that `String(data:encoding:)` dropped, and the
    SARIF column test caught the shift, so the mark is stripped before parsing. `cacheMisses` is still counted under
    `--no-cache`, because the golden records it.
- **Step B** (red `c61a3ef`, green `7a764ed`).
  - **Stores.** They open through `IndexStoreSession`, with the database under the cache root rather than in an
    `IndexDatabase/` beside the store. They are found and named through `IndexStoreLocation`, so a build directory
    resolves to its store and `.build/out` is found.
  - **Auto-build.** `--index-store-build` runs through `BoundedProcess`.
  - **Deleted forks.** `ProcessExecutor`, the trust shim, `IndexStoreFallbackManager`, `IndexStorePathFinder` and
    `IndexStoreLocator` are gone.
  - **Staleness.** The session's coverage is the run-wide gate. Checking freshness a second time on top of it had
    cost 20 s of CPU on maintastic.

Reports are byte-equal to the release on analyzerkit's sources and maintastic, in xcode, JSON and SARIF, with and
without an index store, and the goldens are unchanged. The one difference is on stderr: the index run on analyzerkit
now finds `.build/out` and uses it, still with 0 findings. 228 tests pass, with a 400 MB peak.

Timings on maintastic, debug build:

- **No cache:** 7.85 s cold.
- **Warm cache:** 0.70 s, the same 3 findings.
- **With the Xcode store:** 7.4 s real and 52 s user, as before.
