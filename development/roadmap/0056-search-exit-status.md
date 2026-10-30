---
status: done
blocked-by: []
date: 2026-10-30
---

# 0056 — `ExitStatus.noMatch` (P12)

ADR-0026. `AnalyzerCLI.ExitStatus.noMatch` (1), documented as the status of a search that ran and matched nothing;
the status table in `docs` gains a "search commands" column.

Red: a golden of the table (values and meanings) that fails until the case and its documentation exist; `noMatch` and
`findings` share a raw value and differ only in name and documentation.

## Done

`ExitStatus.noMatch` is a static alias of `findings`, not a case: Swift refuses two cases with one raw value, and a
case would have changed `allCases`, the sysexits list consumers read. `SearchOutcome.status(matchCount:analyzedFileCount:
skippedFileCount:)`: 0 when something matched (index matches count with no file read), 70 when nothing matched and
every file found was skipped, else 1. 3 tests (`SearchOutcomeTests`), red at `521f46a`. There is no status table in
`docs` to extend; ADR-0018 and ADR-0026 are the table. swift-search takes it in its 0006.
