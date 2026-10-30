---
status: done
blocked-by: []
date: 2026-10-29
---

# 0021 — Migrate fcheck to the shared foundations (wave 1)

Repository: g-cqd/fcheck. Scope: replace (or, where the tool has none, adopt) the tool's own discovery, path filter, report formatter, baseline, path
presentation, suppression, command-line options and facts cache with analyzerkit's (ADR-0016); read
`.swift-analyzers.json`; keep the old flag spellings as aliases. `cacheNote` stays beside `notes` until wave 3; `--include-tests` becomes an alias of `--include-regions test`.

Red: golden reports (xcode, JSON, SARIF, baseline) recorded from the current release on the tool's fixture corpus and on a
pinned snapshot of a g-cqd package; the migrated tool must match them byte for byte apart from added keys. The shared
`--help` and exit-code goldens of 0013 fail until the migration lands.

Acceptance: goldens green; the tool's suite green; its own copies of the replaced files deleted; timings on maintastic before
and after in the tool's diary.

Also (from 0014): with the shared output options, `--verbose` prints `SharedConfiguration.Resolved.verboseLines`;
fcheck discards them until then.

From 0016: `CorpusScanner.scan` takes `cache: CacheLocation` (root from `--cache-path` or `CacheLocation.defaultRoot`, the
workspace, the budget) and a `CacheIdentity`; `FactsCache` is gone, so the tool's own cache moves onto the container.

From 0043: `ProjectClassification.load(layout)` once per run, then `classify(path, tree:)` per file, replaces the
`TestConventions` and `GeneratedCode` calls in `FCheckCore` `Analyzer.swift`. Its `issues(for:)` (`project-unknown`, `project-unclaimed`)
become run notes. 0043's acceptance that every tool selects the same regions for the same fixture and configuration is
checked here, by a shared fixture each migration runs.

## Done

fcheck red `0e86471`, green `f58b04e`, on analyzerkit `d535d92`, aemi `2fbe4e4`, AemiJSON `b59ce29`.

- **Options.** `analyze` takes the Input, Output, Rules and Cache groups (ADR-0019). Every option works:
  - `--exclude-path` is a second `PathFilter` rooted at the current directory.
  - `--include-regions` and `--exclude-regions` replace the file's lists side by side.
  - `--report-new-since` goes through `NewSince` (ADR-0028, written for this) and requires `--only`.
  - `--verbose` prints `verboseLines` and every path of a note; `--quiet` and `--timings` (JSON `timings` and stderr)
    work as described.
  - `rules <id>` explains a rule, as `explain` does.
  - `--include-tests` stays as a hidden alias that prints the deprecation line.
  - `--define` is accepted and says it has no effect, because fcheck reads every `#if` clause: 0059.
- **Help.** `Goldens/help-analyze.txt` pins it. It was recorded from the migrated build, so it is a guard, not a red test.
- **Regions** (0043). `ProjectClassification` decides first: paths before the scan, so a test target is never parsed; then
  content, during extraction (`FileResult.region`), so a test-framework import outside `Tests/` is test code. Regions
  stay out of the cache salt: they choose which files are reported, not what a file's facts are.
  `project-unknown` and `project-unclaimed` become run notes, one stderr line each.
- **Cache.** The cache moved onto `CacheLocation` (ADR-0011). `--cache-path` is now the root directory, and its shared
  help said "file" until `d535d92`. The default root is `~/Library/Caches/fcheck`; the old `~/.cache/fcheck` is no longer
  read or cleaned.
- **Not replaced.** Report, baseline and suppression were already thin layers over `ReportSupport` and `Suppression`
  (0011, 0012).

Byte comparison: debug builds of `65d16c7` and `f58b04e`, `--no-cache`, xcode, JSON and SARIF.
- analyzerkit's `Sources`: stdout, stderr and status identical.
- maintastic (`parts-MAIN-24752-stock-handling`), runs taken together because the checkout is live:
  - findings identical in every format;
  - 18 fewer files analysed (2,589 to 2,571; 2,981 to 2,963 with `--include-tests`): the 17 package manifests and
    `scripts/clean_localizable_full.swift`, which a build phase runs. They are `script` now, and
    `--include-regions script` brings them back;
  - one new note: 2 files (`Dangerfile.swift`, `Dangerfile.hooks.swift`) are in a project no target compiles.

Tests: 108 pass, plus the report goldens. Not done:
- maintastic timings: load averages of 100 to 700 make them meaningless.
- 0043's shared region fixture, run by every tool: fcheck has its own `ProjectRegionTests`.
- Linux.
