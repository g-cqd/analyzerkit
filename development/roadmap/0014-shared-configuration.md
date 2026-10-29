---
status: in-progress
blocked-by: []
date: 2026-10-29
---

# 0014 — `.swift-analyzers.json`

Scope (ADR-0020): reader with precedence (defaults, shared top level, tool section, tool file, flags), concatenated
`exclude`, unknown keys rejected with exit 78 naming file and key, `--verbose` printing the sources of each overridden value.

Red: precedence table tests; the configuration directory rule; an unknown key at the top level, in the tool's section or in
the tool's file fails with 78 in each tool (fails today: every tool ignores it); maintastic's three files expressed as one shared file give
the same file selection per tool.

Acceptance: tests green; a sample `.swift-analyzers.json` in `docs/` for users.
