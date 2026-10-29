---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0013 — `AnalyzerCLI`: one command-line surface

Scope (ADR-0006): option groups (input, output, rules, cache, index, experimental), unified exit codes
(0/1/64/70/74/78), hidden aliases with a stderr deprecation line, `--verbose` (which also lifts `RunNote`'s ten-path
cap, from 0011), `--quiet`, `--timings`, the stderr writer.

Red: golden `--help` of each tool's analysing command (fails today: the groups differ); an exit-code table test per tool
(modeler returns 1 for an unreadable configuration today, not 78).

Acceptance: goldens and the exit-code table green for the five tools after their migration (0018–0022).
