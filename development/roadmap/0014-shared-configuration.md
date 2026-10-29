---
status: done
blocked-by: []
date: 2026-10-29
---

# 0014 — `.swift-analyzers.json`

Scope (ADR-0020, as ADR-0021 amends it): reader with precedence (defaults, shared top level, tool section, tool file,
flags), concatenated `exclude`, unknown keys rejected with exit 78 naming file and key, `--verbose` printing the sources of
each overridden value.

Red: precedence table tests; the configuration directory rule; an unknown key at the top level, in the tool's section or in
the tool's file fails with 78 in each tool (fails today: every tool ignores it); maintastic's three files expressed as one shared file give
the same file selection per tool.

Acceptance: tests green; a sample `.swift-analyzers.json` in `docs/` for users.

## Done

Diary 2026-10-29-17. Decisions from probes of the four configurable tools: ADR-0020 supersedes ADR-0007 (no tool
rejected an unknown key; every tool read only the current directory; no tool reads index-store or cache keys), then
ADR-0021 supersedes ADR-0020's lookup after it stalled deadwood's suite (see the diary).

analyzerkit `AnalyzerConfiguration` (new product): red `5eabd02` → `70776a8`; `--verbose` lines `bf608d8` → `49220d8`;
failure reasons `fea7f85` (its red commit was never seen failing: that run died on a full disk; the stub could not have
passed the test, but this is inference, not observation); a key given twice: red, then `88742f9`; stat-only lookup
`839d8ba` → `e98a332`; the sample `docs/.swift-analyzers.json`, checked by a test and by the four binaries.

Adopted, red then green: arcleak `83e20d9` → `e877507`, deadwood `507e8c2` → `2cf136f`, dolly `3f15e6c` → `bfc348c`,
fcheck `8879b02` → `47495be`. Full suites green: arcleak 229, deadwood 387, dolly 211, fcheck 92. READMEs of the five
tools now describe the shared file, and the exit statuses of 0013, which they had not been updated for.

maintastic, read-only: its three files expressed as one shared file (common excludes at the top level, the rest in
sections), passed with `--config`, give byte-identical JSON reports to the three files in arcleak (2,837 files, 3
findings), deadwood (2,980, 57) and dolly (2,880, 244). maintastic itself is unchanged.

Release notes: a configuration with an unknown or repeated key now exits 78 in the four tools (none of the files in use
has one); the configuration is found from a subdirectory too, nearest first; fcheck reads `includeRegions`.

Deferred: `--verbose` for dolly and fcheck arrives with their shared output options (0020, 0021); modeler's section with
its configuration (0022); `indexStore` and `cache` keys with 0010 and 0016.
