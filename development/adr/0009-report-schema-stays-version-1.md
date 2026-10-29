---
status: accepted
date: 2026-10-29
---

# 0009 — The report schema stays version 1; it only grows

## Context

Consumers decode the JSON report and refuse other versions: maintastic's `StaticAnalysisReport` checks
`schemaVersion == 1` and reads `findings[].{path, line, message, note, rule, severity, related[].{path, line}}`. The
reports ask for notes in the JSON (arcleak has none, deadwood has `notes: [String]`, dolly `contextNote`, fcheck
`cacheNote`) and for the files that were not checked. The owner chose to keep version 1.

## Decision

1. `schemaVersion` stays 1. Existing keys keep their names, types and meaning.
2. Added keys, all optional for a reader: `tool` (name, version), `notes` (array of `{code, severity, message, count,
   paths}`; `paths` holds at most ten entries unless `--verbose`), `skippedFiles` (array of `{path, reason}` with reason
   `notIndexed`, `changedSinceBuild`, `unreadable`, `degraded`), `timings` (with `--timings`).
3. `contextNote` (dolly), `cacheNote` (fcheck) and deadwood's `notes: [String]` are kept for one minor release beside the
   new `notes`, then removed in the release that removes the flag aliases (ADR-0015, wave 3). deadwood's `notes` changes
   type in that release; that is the one breaking change of the schema and it is announced two releases ahead.
4. Baseline fingerprints and SARIF output do not change byte for byte; golden files pin them.

## Consequences

- A consumer that ignores unknown keys (Swift's `JSONDecoder` does) needs no change.
- The xcode-format summary line gains "(N not checked)" when files were skipped.
