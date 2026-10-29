---
status: done
blocked-by: []
date: 2026-10-29
---

# 0005 — `PathFilter`: one exclusion rule for every tool

Scope (ADR-0008): substring entries keep their meaning; entries with `*`, `?` or `[` are globs (`**` across components,
leading `/` anchors at the project root), matched over UTF-8 bytes without a regular expression; directory pruning during
the walk. Adopted now by the four tools with `exclude`; modeler gains the surface in 0014/0022.

Red: a table of (entry, path, expected) covering every current configuration on maintastic and the g-cqd packages, and the
`MyPackage.swift` case; a fixture tree on which the five tools must select the same files (fails today: 2,584 to 2,973 on
maintastic).

Acceptance: the shared matcher and pruned/filtered walks agree on the fixture tree; existing substring configurations
keep the same file selection on maintastic. Tool corpus-scope differences are unified in 0013, not hidden here.

## Done

Diary 2026-10-29-10. analyzerkit `b760211` red, `09d33f2` green, `e1728a8` red for a symlink root,
`95d45fc` green. `PathFilter` in SourceCorpus: byte substrings without metacharacters; root-relative globs otherwise;
whole-scalar `?` and classes; component `**`; directory ancestors; root as given and canonical. Table tests, kept-file
goldens, five pruned-versus-filtered walks, symlink-root regression all green.

Each adopting tool has a red then green commit and pins `95d45fc`: arcleak `8b7520f` (207 tests), dolly `10d62d8`
(194), fcheck `c687f56` (73), deadwood `ec5831a` (365). Loaded configuration carries its directory as `root`, not
encoded; one filter per run. The first three prune discovery; arcleak and fcheck also filter explicitly supplied files.
Dolly's explicit-file bypass is tracked by 0013. Deadwood intentionally still reads excluded files, filtering findings
and out-of-scope entries only; its remaining `GlobMatcher` users are replaced in 0019.

Release binaries on today's maintastic: dolly 2,874 files, arcleak 2,831, deadwood reads all 2,974; independently
recomputing the previous substring selection on the same tree gives exactly those counts (deadwood's report scope:
2,885 files). fcheck: 2,585 files, one finding. No maintastic files changed. Modeler has no `exclude` yet; adoption
belongs to shared configuration (0014) and its migration (0022), not a new tool-specific surface here.
