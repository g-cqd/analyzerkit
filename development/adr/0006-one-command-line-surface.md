---
status: superseded
superseded-by: ADR-0019
date: 2026-10-29
---

# 0006 — One command-line surface, from shared option groups

## Context

The five tools grew their flags apart (research `2026-10-29-surface-and-duplication.md`): `--exclude` is a *region* on the
command line of arcleak, deadwood and dolly but a *path* in their configuration files; fcheck and modeler say
`--include-tests`; `--define` exists only in arcleak although `#if` matters to every tool; `--report-new-since` only in
deadwood; `--rules` and `explain` only in fcheck; `modeler check` has no `--format`, `--baseline` or `--relative-to`; no tool
has `--verbose` or `--timings`; the embeddings are spelled three ways. Exit codes differ: arcleak returns 1/70/74/78,
deadwood and dolly 1/70/78, fcheck 1/64, modeler 1.

## Decision

A new analyzerkit target, `AnalyzerCLI`, provides ArgumentParser option groups that every tool's analysing command uses:

| Group | Options |
| --- | --- |
| Input | `<paths…>`, `--config <file>`, `--exclude-path <pattern>` (repeatable), `--include-regions <list>`, `--exclude-regions <list>`, `--define <name>` (repeatable), `--only <file>`, `--only-from <file>` |
| Output | `--format xcode\|json\|sarif`, `--relative-to <dir>`, `--strict`, `--baseline <file>`, `--write-baseline <file>`, `--report-new-since <git ref>`, `--verbose`, `--quiet`, `--timings` |
| Rules | `--rules <list>`, and the subcommands `rules` and `explain <id>` |
| Cache | `--cache-path <dir>`, `--no-cache` |
| Index | `--index-store`, `--index-store-path <path>`, `--index-store-build` |
| Experimental | `--experimental-embeddings <rank\|confidence\|semantic>` and `--embedding-bundle <path>` |

Exit codes, for every tool: 0 clean or findings without `--strict`; 1 findings that fail the run; 64 usage; 70 internal
failure or nothing analyzed; 74 an output that could not be written; 78 a configuration or baseline that cannot be read.

Renamed flags stay as hidden aliases for one minor release and print a one-line deprecation note on stderr:
`--include`/`--exclude` (regions) → `--include-regions`/`--exclude-regions`; `--include-tests` → `--include-regions test`;
`--experimental-embedding-rank`, `--experimental-embedding-confidence`, `--semantic` → `--experimental-embeddings`.

## Consequences

- A golden test in analyzerkit renders each tool's `--help` and fails when a shared option drifts.
- Tool-specific options stay (arcleak `--fix`, deadwood `--production` and `--minimum-confidence`, dolly's duplication
  thresholds), listed after the shared groups.
- Deprecation notes go to stderr only; stdout (the report) is unchanged, so parsers are not affected.
