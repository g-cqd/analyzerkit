---
status: not-started
blocked-by: [0001]
date: 2026-10-29
---

# 0036 — The five tools adopt the records layout

Repositories: arcleak, deadwood, dolly, fcheck, modeler. Scope: each gets `development/` (white paper, ADRs, roadmap,
diary, research) for decisions about that tool alone (ADR-0001 item 3), its existing design notes (`Docs/`, `DESIGN.md`)
moved or linked, and the `DocumentationLayout` test of 0001. A tool's first ADRs record the decisions already in its code
and README; they are written from the code, not invented.

Red: the test on each tool before its records exist (no white paper) fails.

Acceptance: green in each tool's CI.
