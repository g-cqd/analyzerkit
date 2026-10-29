# 2026-10-29 — Surface differences and duplicated code across the tools

## Analysing command, flags (from `--help` of the current releases)

| Flag | arcleak | deadwood | dolly | fcheck | modeler `check` |
| --- | --- | --- | --- | --- | --- |
| `--config` | ✓ | ✓ | ✓ | ✓ | — |
| `--format` | ✓ | ✓ | ✓ | ✓ | — |
| `--relative-to`, `--strict` | ✓ | ✓ | ✓ | ✓ | `--strict` only |
| `--baseline`, `--write-baseline` | ✓ | ✓ | ✓ | ✓ | — |
| `--only`, `--only-from` | ✓ | ✓ | ✓ | ✓ | — |
| `--cache-path`, `--no-cache` | ✓ (file) | ✓ (file) | ✓ (file) | ✓ (file) | ✓ (file) |
| regions | `--include`/`--exclude` | `--include`/`--exclude` | `--include`/`--exclude` | `--include-tests` | `--include-tests` |
| `--define` | ✓ | — | — | — | — |
| `--report-new-since` | — | ✓ | — | — | — |
| `--rules` / `explain` | — / — | — / — | — / — | ✓ / ✓ | — / — |
| index | `--index-store*` | `--index-store*` | — | — | — |
| embeddings | `--experimental-embedding-rank` | `--experimental-embedding-confidence` | `--semantic`, `--embedding-preset` | — | — |
| `--verbose`, `--timings` | — | — | — | — | — |

The same word means two things: `--exclude` on the command line is a region, `exclude` in the configuration file is a path.

## Exit codes

arcleak 0/1/70/74/78; deadwood and dolly 0/1/70/78; fcheck 0/1/64; modeler 0/1 (64 from ArgumentParser for all).

## Configuration

| Key | arcleak | deadwood | dolly | fcheck |
| --- | --- | --- | --- | --- |
| `exclude` | substring | substring or glob | substring | substring |
| `includeRegions`, `excludeRegions` | ✓ | ✓ | ✓ | `includeTests` |
| `rules`, `severity` | ✓ | ✓ | ✓ | `disable`, `severity` |
| own | `defines`, `platforms`, `contracts` | `production`, `testsGlob` | `duplication` | `resources`, `flush` |

modeler has no configuration file. On maintastic the same project yields 2,584 to 2,973 analysed files depending on the tool.

## Report

JSON keys: arcleak `analyzedFileCount, cacheHits, cacheMisses, degradedFiles, findings, outOfScope, schemaVersion,
suppressed, wasCancelled`; deadwood adds `notes: [String]`; dolly `contextNote: String?`; fcheck `cacheNote`.

## Duplicated code (similarity after whitespace normalisation)

| File | Copies | Similarity |
| --- | --- | --- |
| `SuppressionTable` | arcleak, deadwood, dolly | 100 % |
| `DirectiveScanner` | deadwood, dolly | 98 % |
| `Baseline` | arcleak, deadwood, dolly (fcheck own) | 86–92 % |
| `ReportFormatter` | arcleak, deadwood, dolly (fcheck own) | 85–89 % |
| `SuppressionDirective` | arcleak, deadwood, dolly | 84–88 % |
| `AnalysisReport` | arcleak, deadwood, dolly | 69–90 % |
| `PathPresentation` | arcleak, deadwood, dolly | 54–84 % |
| embedding providers (NL, HF, deterministic) | arcleak, deadwood, dolly | 41–80 % |
| `IndexStoreReader`, fallback, `ProcessExecutor`, `BinaryTrustChecker` | arcleak, deadwood | 31–48 % |
| `FactsCache` | arcleak, deadwood, dolly vs `CorpusScan` | 23–48 % |
| `AtomicBitmap`, BFS, frontier expansion, concurrency config | deadwood, dolly | 50–70 % |
