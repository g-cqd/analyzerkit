---
status: done
blocked-by: []
date: 2026-10-29
---

# 0013 — `AnalyzerCLI`: one command-line surface

Scope (ADR-0019, ADR-0018): option groups (input, output, rules, cache, index, experimental), unified exit codes
(0/1/64/70/74/78), hidden aliases with a stderr deprecation line, `--verbose` (which also lifts `RunNote`'s ten-path
cap, from 0011), `--quiet`, `--timings`, the stderr writer.

Red: golden `--help` of each tool's analysing command (fails today: the groups differ); an exit-code table test per tool,
the scenarios of `research/probes/exit-codes.py` (fails today: fcheck passes error findings and nothing read, exits 64 for a
bad configuration; modeler exits 0 for a missing path and for nothing read; three tools exit 78 for an unwritable
baseline).

Acceptance: the exit-code table green in the five tools; the option groups and their help golden green in analyzerkit.
Each tool's own `--help` golden is the red of its migration (0018–0022), which adopts the groups.

## Done

Diary 2026-10-29-16. Two decisions first, each from a probe of the five shipped commands: ADR-0018 (which findings fail
a run, and the six statuses: `research/probes/exit-codes.py`) and ADR-0019, superseding ADR-0006 (four of its option lines
were wrong against what ships).

analyzerkit `AnalyzerCLI` (new product): `ExitStatus` and `RunOutcome` (red, then `191f426`); the six option groups with
their titles, hidden aliases folded in and listed as `Deprecation`s, and contradictions as usage errors (red, then
`4b89b38`), the shared help pinned in `Tests/AnalyzerCLITests/Goldens/help.txt`.

Exit-code table, red then green, in every tool: arcleak `3f3f092` → `620d914`, deadwood `d20c843` → `862633b`, dolly
`0077285` → `9bbc7c8`, fcheck `a754706` → `e2691a7`, modeler `84ed1dc` → `8f40eca` (which also moved modeler's analyzerkit
pin from `65b105d` to `191f426`). The probe now reads the same in every column except files that are not UTF-8 (0045).
Full suites green: arcleak 224, deadwood 382, dolly 207, fcheck 87, modeler 63.

Behaviour changes, for the release notes: fcheck fails on an error finding without `--strict`, exits 78 for a bad
configuration or baseline, 74 for an unwritable baseline and 70 when it read nothing; modeler exits 64 for a missing path
or no Swift file and 70 when it read nothing; arcleak, deadwood and dolly exit 74 instead of 78 for an unwritable baseline.

Not here, by design: the tools' adoption of the groups (their migrations), wiring `--quiet` and `--timings` and
`--verbose`'s lifting of `RunNote`'s cap (with that adoption). The shared stderr writer is dropped: each tool's is two
lines over its own `FileDescriptor`, and sharing it would add a dependency to analyzerkit for nothing.
