---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0041 — A deeply nested file crashes every tool

Found during 0035 (diary 2026-10-29-08). One file holding a long method chain (`view.modifier(1).modifier(1)…`) kills the
whole run with SIGBUS (exit 138): deadwood from 1,000 links, arcleak, dolly, fcheck and modeler from 3,000. In a test
thread fcheck dies at 300: swift-syntax's `SourceLocationConverter(fileName:tree:)` recurses once per level of the tree,
and the per-file work runs on threads with small stacks. One generated or hostile file is enough to lose the report, and a
CI that treats 64/70/74/78 as "did not run" (maintastic) sees an unexpected status instead.

Scope: a file is either analysed or reported as degraded ("nested too deeply"), never a crash. Candidates, to measure
first: run the per-file work on threads with a large stack (shared by every tool through `CorpusScan`); an iterative
depth check of the tree before anything recursive walks it, with a limit well above real code; both.

Red: a corpus of one 3,000-link chain and one ordinary file: each tool exits normally, analyses the ordinary file and lists
the deep one as degraded (fails today with exit 138).

Acceptance: the red test green in every tool; the limit and the stack size recorded with their measurements.
