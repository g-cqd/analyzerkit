---
status: done
blocked-by: []
date: 2026-10-29
---

# 0005 — `PathFilter`: one exclusion rule for every tool

Scope (ADR-0008): substring entries keep their meaning; entries with `*`, `?` or `[` are globs (`**` across components,
leading `/` anchors at the project root), matched over UTF-8 bytes without a regular expression; directory pruning during
the walk. Adopted now by the four tools with `exclude`; modeler gains the surface in 0014/0022.

Red: a table of (entry, path, expected) covering every current configuration on the reference app and the g-cqd packages, and the
`MyPackage.swift` case; a fixture tree on which the five tools must select the same files (fails today: 2,584 to 2,973 on
the reference app).

Acceptance: the shared matcher and pruned/filtered walks agree on the fixture tree; existing substring configurations
keep the same file selection on the reference app. Tool corpus-scope differences are unified in 0013, not hidden here.

## Done

Diary 2026-10-29-10. analyzerkit `6ecab42` red, `c3e5d5b` green, `c311b5f` red for a symlink root,
`26342ee` green. `PathFilter` in SourceCorpus: byte substrings without metacharacters; root-relative globs otherwise;
whole-scalar `?` and classes; component `**`; directory ancestors; root as given and canonical. Table tests, kept-file
goldens, five pruned-versus-filtered walks, symlink-root regression all green.

Each adopting tool has a red then green commit and pins `26342ee`: arcleak `a815877` (207 tests), dolly `411c2a1`
(194), fcheck `2f207db` (73), deadwood `a572234` (365). Loaded configuration carries its directory as `root`, not
encoded; one filter per run. The first three prune discovery; arcleak and fcheck also filter explicitly supplied files.
Dolly's explicit-file bypass is tracked by 0013. Deadwood intentionally still reads excluded files, filtering findings
and out-of-scope entries only; its remaining `GlobMatcher` users are replaced in 0019.

Release binaries on today's the reference app: dolly 2,874 files, arcleak 2,831, deadwood reads all 2,974; independently
recomputing the previous substring selection on the same tree gives exactly those counts (deadwood's report scope:
2,885 files). fcheck: 2,585 files, one finding. No the reference app files changed. Modeler has no `exclude` yet; adoption
belongs to shared configuration (0014) and its migration (0022), not a new tool-specific surface here.
