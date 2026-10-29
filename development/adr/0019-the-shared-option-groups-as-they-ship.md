---
status: accepted
date: 2026-10-29
supersedes: ADR-0006
---

# 0019 — One command-line surface: the shared option groups, corrected against what ships

## Context

ADR-0006 set the shared option groups. Checked against the five shipped commands before building them (roadmap 0013,
diary 2026-10-29-16), four of its lines were wrong: deadwood's `--report-new-since` takes the base branch's *baseline
file*, not a git ref; fcheck's and modeler's `--include-tests` means test **and generated** code, so an alias to
`--include-regions test` would silently drop generated code; dolly's `--semantic` turns on a rule (semantic clones) with
its own options, unlike arcleak's ranking and deadwood's confidence, which are experiments that never change which
findings fire; and fcheck's `explain <id>` is the other three tools' `rules <id>`. ADR-0018 since fixed the exit statuses.

## Decision

`AnalyzerCLI` provides these ArgumentParser option groups; every tool's analysing command uses them, in this order:

| Group | Options |
| --- | --- |
| Input | `<paths…>` (default `.`), `--config <file>`, `--exclude-path <pattern>` (repeatable, ADR-0008), `--include-regions <list>`, `--exclude-regions <list>`, `--define <name>` (repeatable), `--only <file>` (repeatable), `--only-from <file>` |
| Output | `--format xcode\|json\|sarif`, `--relative-to <dir>`, `--strict`, `--baseline <file>`, `--write-baseline <file>`, `--report-new-since <baseline file>`, `--verbose`, `--quiet`, `--timings` |
| Rules | `--rules <list>` |
| Cache | `--cache-path <file>`, `--no-cache` |
| Index | `--index-store`, `--index-store-path <path>`, `--index-store-build` (index-capable tools) |
| Experimental | `--experimental-embeddings rank\|confidence`, `--embedding-bundle <path>` (embedding-capable tools) |

Subcommands: `rules` lists the rules; `rules <id>` and `explain <id>` explain one, in every tool.

Exit statuses: ADR-0018.

Renamed flags stay as hidden aliases until the alias-removal release of the train (ADR-0015, wave 3), each printing one
line on stderr, `<tool>: note: <old> is deprecated; use <new>`: `--include`/`--exclude` (regions) →
`--include-regions`/`--exclude-regions`; `--include-tests` → `--include-regions test,generated`;
`--experimental-embedding-rank` and `--experimental-embedding-confidence` → `--experimental-embeddings rank|confidence`.

Not shared, listed after the groups: arcleak `--fix`, `--fix-dry-run`, `--stamp`, `--experimental-sil-confirm`; deadwood
`--production`, `--minimum-confidence`; dolly `--semantic`, `--embedding-preset`, `--semantic-max-group` and the
duplication thresholds. modeler's diagram subcommands take the Input and Cache groups only.

## Consequences

- analyzerkit renders a probe command made of the groups and pins its `--help` in a golden; each tool's migration
  (roadmap 0018–0022) pins its own `--help`.
- Deprecation notes go to stderr only; stdout (the report) does not change.
