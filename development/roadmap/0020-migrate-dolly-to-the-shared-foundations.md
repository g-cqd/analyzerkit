---
status: done
blocked-by: []
date: 2026-10-29
---

# 0020 — Migrate dolly to the shared foundations (wave 1)

Repository: g-cqd/dolly. Scope: replace (or, where the tool has none, adopt) the tool's own discovery, path filter, report formatter, baseline, path
presentation, suppression, command-line options and facts cache with analyzerkit's (ADR-0016); read
`.swift-analyzers.json`; keep the old flag spellings as aliases. `contextNote` stays beside `notes` until wave 3.

Red: golden reports (xcode, JSON, SARIF, baseline) recorded from the current release on the tool's fixture corpus and on a
pinned snapshot of a g-cqd package; the migrated tool must match them byte for byte apart from added keys. The shared
`--help` and exit-code goldens of 0013 fail until the migration lands.

Acceptance: goldens green; the tool's suite green; its own copies of the replaced files deleted; timings on maintastic before
and after in the tool's diary.

Also (from 0014): with the shared output options, `--verbose` prints `SharedConfiguration.Resolved.verboseLines`;
dolly discards them until then.

From 0016: `CorpusScanner.scan` takes `cache: CacheLocation` (root from `--cache-path` or `CacheLocation.defaultRoot`, the
workspace, the budget) and a `CacheIdentity`; `FactsCache` is gone, so the tool's own cache moves onto the container.

From 0043: `ProjectClassification.load(layout)` once per run, then `classify(path, tree:)` per file, replaces the
`TestConventions` and `GeneratedCode` calls in `DollyCore` `Engine/FileContext.swift`, `CloneReporting.swift`, `Analyzer.swift`. Its `issues(for:)` (`project-unknown`, `project-unclaimed`)
become run notes. 0043's acceptance that every tool selects the same regions for the same fixture and configuration is
checked here, by a shared fixture each migration runs.

## Done

dolly red `1ec69c4`, green `b897fad`, on analyzerkit `4585088`. Two analyzerkit additions came first, each red first:

- `CorpusScanner.scan(keepingBytes:)` (`7338d61`) hands back the bytes it read, on a hit as on a miss. dolly rebuilds
  its token text from the cached facts and the source, and embeds snippets of it, so it needs every file's text after
  the scan.
- `ProjectClassification.contentRegion(path:tree:)` and `classify(_:content:)` (`abc0393`) split a file's region into
  the part its content decides, which a cache keyed by content may keep, and the part its project decides, which changes
  without the file changing and is joined on every run.

In dolly:

- **Cache.** `FactsCache` is deleted. Its entry is now `CachedFileFacts`: tokens, directives, the content region and
  previews, plus a degraded reason, so a file that is not UTF-8 or nests too deeply is never re-parsed only to fail
  again. They are stored through `CorpusScanner` on `CacheLocation`, so `--cache-path` is a root directory. Extraction
  depends on no configuration, so changing rules or thresholds now reuses every file; before, any configuration change
  emptied the cache. The cache's own tests (corruption, identity, pruning, size) are analyzerkit's now.
- **Options.** `analyze` takes the four shared groups, with `--semantic` and the embedding options after them.
  - `--include`/`--exclude` are deprecated aliases that print a note.
  - `--exclude-path`, `--rules`, `--report-new-since` (through `NewSince`), `--verbose`, `--quiet` and `--timings` are
    new.
  - `--define` says it has no effect: clones compare the tokens of every clause.
  - The `--only-from` split moved to `Character.isNewline` (0057).
- **Regions.** Classification comes from the project (0043): `project-unknown` and `project-unclaimed` become run notes.

Found on the way: `ProjectClassification.ancestors(of:)` never ended for a relative path, because `parent(".")` is
`.`. dolly's single-source entry point names its file `t.swift`, so three of its suites grew past 3 GB until the run
died. Fixed in analyzerkit `4585088`, red first (the red run was killed at a 625 MB cap). dolly's 213 tests pass with a
353 MB peak.

Comparison: debug builds of `7e82e0a` and `b897fad`, `--no-cache`, xcode, JSON and SARIF.

| Corpus | Result |
| --- | --- |
| analyzerkit `Sources` | stdout, stderr and status identical |
| maintastic | findings identical in every format (244); one new note: 1 file a project encloses that no target compiles |
| maintastic, cache cold then warm (debug, loaded) | 14.3 s and 7.2 s, 2,881 files reused, the same 244 findings; cache 26 MB |

Not done: release timings, Linux, the old `~/Library/Caches/dolly/<workspace>/facts.json` files (no longer read or
removed).
