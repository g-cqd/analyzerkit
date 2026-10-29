---
status: done
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

## Done

Diary 2026-10-29-09. Measured first, in a debug build: on a 256 MiB stack, parsing, swift-syntax's location converter
and a full visitor take a 100,000-link chain (about 200,000 levels) and die at 200,000 links; parsing alone survives
30,000 links on a test thread, so only the walks need the stack. Both candidates, together:

- analyzerkit `LargeStack.run` (`SourceCorpus`, `a1e64c8` red, `65b105d` green): the body runs on a detached POSIX
  thread with a 256 MiB stack, reserved not committed, and resumes a continuation. `CorpusScanner` extracts every cache
  miss on it (`LargeStackScanTests`, `d9fc447`); a hit never parses and stays on the task.
- analyzerkit `SyntaxDepth.exceeds(_:limit:)` (`ProjectModel`, `8405e42`): an explicit-stack walk, limit 20,000 levels
  (about 10,000 chained calls, a tenth of what the large stack holds). A deeper file is listed, not walked.
- Each tool, red first (a 3,000- and a 15,000-link chain beside an ordinary file; dolly 1,000 links, still a crash
  before the fix): fcheck `70d627f` (`FileResult.degraded`, the second pass on the large stack too), modeler `0a834c8`
  (`FileFacts.degraded`, absent from encoded facts when nil; `Corpus.Report.degraded`), arcleak `e68c71d` (extraction,
  the index upgrade pass and the corpus rules on the large stack; a too-deep declaring file is `.gone` to the
  resolver), deadwood `bdbbf1e` (depth measured after operator folding; a skipped `DegradedFile`), dolly `014ec2f`
  (cache misses and the single-file entry point on the large stack). All pin analyzerkit `65b105d`; pushed.

Cost on maintastic, release: fcheck cold 0.43–0.59 s wall, 1.16–1.23 s user (0.57 s and 1.27 s before). deadwood
against the commit before its fix, interleaved: identical output, wall within noise (3.37–4.35 s against 3.42–4.66 s),
user about 1 s more (9.52–10.37 s against 8.35–9.10 s) — the extra walk over 2,974 files, absorbed by the cores. Its
budget belongs to 0029. deadwood's synchronous `analyze(source:path:)` keeps the caller's stack, guard only (no CLI
caller). dolly's engine is superlinear on self-similar input, found by the red test: 0042.
