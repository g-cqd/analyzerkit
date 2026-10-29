---
status: accepted
date: 2026-10-29
supersedes: ADR-0009
---

# 0017 — The report schema stays version 1, and its added keys never collide with shipped ones

## Context

ADR-0009 kept `schemaVersion` 1 and added `tool` (an object of name and version), `notes` (an array of objects),
`skippedFiles` and `timings`. Implementing it (roadmap 0011, diary 2026-10-29-14) against the shipped reports showed two
of those names already taken: deadwood writes `notes` as an array of strings, fcheck writes `tool` and `version` as strings.
Following ADR-0009 would retype both, the change its own first rule forbids, and its plan to change deadwood's `notes`
later would have been the schema's one breaking change. `ReportSchema` also counts the removal of a key as a version
change, so the old keys cannot be dropped inside version 1 either.

Two more facts from the same survey. Baseline files differ: arcleak, deadwood and dolly write `{fingerprints, tool,
version}`, fcheck `{fingerprints, tool}`. Each tool hashes its own fields into its fingerprints (FNV-1a in four of them);
ADR-0016's "XXH64 replaces FNV-1a where they fingerprint" would invalidate every baseline in use.

maintastic, the one external consumer, decodes `schemaVersion` and `findings[].{path, line, message, note, rule,
severity, related[].{path, line}}` and ignores the rest (its `StaticAnalysisReport`).

## Decision

1. `schemaVersion` stays 1 for as long as no key is removed, renamed or retyped. Existing keys keep their names, types and
   meaning, deprecated ones included: they stay for the life of version 1.
2. Added keys, optional for a reader, written by every tool:
   - `tool` and `version`: strings, the tool's name and version, as fcheck already writes them;
   - `runNotes`: an array of `{code, severity, message, count, paths}` about the run rather than one finding; `paths`
     holds at most ten entries unless `--verbose`;
   - `skippedFiles`: an array of `{path, reason}`, reason one of `notIndexed`, `changedSinceBuild`, `unreadable`,
     `degraded`;
   - `timings`, only with `--timings`.
3. deadwood's `notes: [String]`, dolly's `contextNote` and fcheck's `cacheNote` stay unchanged and are also reported as
   `runNotes`. Nothing in the schema changes type.
4. SARIF output, baseline files and fingerprints do not change, byte for byte; golden files in each tool pin them. A tool
   keeps its own fingerprint inputs and hash; analyzerkit shares the baseline file codec (with or without its `version`
   key, as each tool writes it today), not the fingerprint. XXH64 replaces FNV-1a only where a hash is not persisted by a
   consumer (cache keys), never in fingerprints, amending ADR-0016 on that point.

## Consequences

- No consumer needs a change; Swift's `JSONDecoder` ignores the added keys, and maintastic's shape is pinned by a test.
- No breaking schema release is planned; ADR-0015's wave 3 removes flag aliases, not report keys.
- The xcode-format summary line gains "(N not checked)" when files were skipped.
