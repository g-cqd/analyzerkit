---
status: done
blocked-by: []
date: 2026-10-29
---

# 0022 — Migrate modeler to the shared foundations (wave 1)

Repository: g-cqd/modeler. Scope: replace (or, where the tool has none, adopt) the tool's own discovery, path filter, report formatter, baseline, path
presentation, suppression, command-line options and facts cache with analyzerkit's (ADR-0016); read
`.swift-analyzers.json`, gaining suppression through analyzerkit `Suppression` (it has none today) and `exclude` through `SourceCorpus.PathFilter` (modeler has no exclusion surface today); keep the old flag spellings as aliases. `check` gains `--config`, `--format`, `--relative-to`, `--baseline`, `--write-baseline` and the exit codes 70/74/78; the other subcommands take the input and cache groups.

Red: golden reports (xcode, JSON, SARIF, baseline) recorded from the current release on the tool's fixture corpus and on a
pinned snapshot of a g-cqd package; the migrated tool must match them byte for byte apart from added keys. The shared
`--help` and exit-code goldens of 0013 fail until the migration lands.

Acceptance: goldens green; the tool's suite green; its own copies of the replaced files deleted; timings on maintastic before
and after in the tool's diary.

From 0016: `CorpusScanner.scan` takes `cache: CacheLocation` (root from `--cache-path` or `CacheLocation.defaultRoot`, the
workspace, the budget) and a `CacheIdentity`; `FactsCache` is gone, so the tool's own cache moves onto the container.

From 0043: `ProjectClassification.load(layout)` once per run, then `classify(path, tree:)` per file, replaces the
`TestConventions` and `GeneratedCode` calls in `ModelerCore` `Corpus.swift`. Its `issues(for:)` (`project-unknown`, `project-unclaimed`)
become run notes. 0043's acceptance that every tool selects the same regions for the same fixture and configuration is
checked here, by a shared fixture each migration runs.

## Done

modeler: goldens `acf657a`, red `733d20b`, green `ef8c0da`, on analyzerkit `d535d92`, AemiJSON `b59ce29`.

- **Goldens first.** `check`'s xcode report and every diagram (`classes`, `states`, `facts`, `tla`) were recorded from the
  pre-migration build on `Goldens/Corpus`, and the migrated build matches them byte for byte. One deliberate change: the
  stderr summary counts 3 files, not 4, because a test file's region is now known before the scan, so it is never read.
- **`check` gained everything modeler did not have.**
  - A rule catalogue: `reentrancy` and `lock-gap` (`modeler rules [id]`, `explain`).
  - `Finding`, fingerprinted on rule, path, method and member (no line).
  - `.modeler.json` through `SharedConfiguration`, with `disable`, `severity`, the shared `exclude` and regions.
  - `@modeler:` / `@md:` suppression on analyzerkit's grammar. It is read only from files with findings, so the cached
    facts did not change.
  - JSON on `ReportEnvelope`, SARIF on the shared model (`modeler/v1` fingerprints), a versioned `BaselineFile`.
  - `--report-new-since` through `NewSince`, and every option of the four groups.
  - Statuses per ADR-0018: findings are warnings unless configured.
- **The diagram commands** take the Input and Cache groups (ADR-0019), so they gain `--exclude-path`, regions and the
  configuration's `exclude`.
- **Regions and cache** as in fcheck (0021): the project first, path before the scan, content after; the cache root via
  `CacheLocation`. `--define` says it has no effect (0059).
- **Order.** `check` sorts findings by path, line and rule; before, it followed the type order.

Comparison with debug builds of `a271b20` and `ef8c0da`, `--no-cache`:

| Corpus | Result |
| --- | --- |
| analyzerkit's `Sources` | `check`, `classes`, `states`, `facts`: identical output, status and summary |
| maintastic | `check`: the same 28 findings (now sorted by path) |
| maintastic | `states`: identical |
| maintastic | `classes` and `facts`: 3 types fewer (`ContentParser`, `LocalizationStringsFile`, `TranslationSessionCache`), all from `scripts/clean_localizable_full.swift`, which a build phase runs: `script` code now |
| maintastic | file counts: 2,981 to 2,571 (2,963 with `--include-tests`), since test files are no longer read; the old count included them |

78 tests pass. Not done: maintastic timings (load) and Linux.
