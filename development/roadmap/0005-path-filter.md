---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0005 — `PathFilter`: one exclusion rule for every tool

Scope (ADR-0008): substring entries keep their meaning; entries with `*`, `?` or `[` are globs (`**` across components,
leading `/` anchors at the project root), matched over UTF-8 bytes without a regular expression; directory pruning during
the walk. Adopted by the five tools in their wave-1 migration (0018–0022).

Red: a table of (entry, path, expected) covering every current configuration on maintastic and the g-cqd packages, and the
`MyPackage.swift` case; a fixture tree on which the five tools must select the same files (fails today: 2,584 to 2,973 on
maintastic).

Acceptance: table green; the five tools agree on the fixture tree and on maintastic.
