---
status: not-started
blocked-by: [0068]
date: 2026-11-01
---

# 0069 — The commands' run skeleton

Step 5 of 0067, second part. `analyze`, `--write-baseline`, `--baseline`, `--only`, `--report-new-since`, exit codes and the
stderr summary run in the same order in arcleak, deadwood and dolly. Step 4 fixed the finding and report protocols this needs,
so a shared `run` can take closures for the parts that differ (the analyzer call, the experimental flags).

Red: each tool's command-line contract tests (exit codes, stdout and stderr for each flag) pass unchanged on the shared
skeleton; a new test pins the order of the baseline, scope and format steps.

Acceptance: the skeleton is in `AnalyzerCLI`; the three commands shrink to their own options and rules; no flag, exit code
or report byte changes.

It waits for 0068 only so the tools are not released twice in a row; it does not depend on it technically.
