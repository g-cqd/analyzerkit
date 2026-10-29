---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0014 — `.swift-analyzers.json`

Scope (ADR-0007): reader with precedence (defaults, shared top level, tool section, tool file, flags), concatenated
`exclude`, unknown keys rejected with exit 78 naming file and key, `--verbose` printing the sources of each overridden value.

Red: precedence table tests; an unknown key in a section fails; maintastic's three files expressed as one shared file give
the same file selection per tool.

Acceptance: tests green; a sample `.swift-analyzers.json` in `docs/` for users.
