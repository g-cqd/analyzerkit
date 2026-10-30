---
status: not-started
blocked-by: [0025, 0026, 0027]
date: 2026-10-29
---

# 0030 — The release train: three waves, one note format

Scope (ADR-0015). For each wave, in order:

1. Tag analyzerkit (`analyzerkit-wave-N` annotated tag on the pinned revision) and pin that revision in the five tools.
2. Release arcleak, deadwood, dolly, fcheck, modeler in that order (wave 1: 0.13.0, 0.12.0, 0.12.0, 0.2.0, 0.2.0; wave 2:
   0.14.0, 0.13.0, 0.13.0, 0.3.0, 0.3.0; wave 3: 0.15.0, 0.14.0, 0.14.0, 0.4.0, 0.4.0) through aemi's `swift-tool.yml`, which
   publishes the two archives, the artifact bundle and their `.sha256`.
3. Write each tool's release note with the fixed sections, every one filled or "none":
   - **Archives**: names, SHA-256 of each archive and of the bundle, bundle checksum as SwiftPM prints it.
   - **Flags**: added, renamed (old spelling still accepted until wave 3), removed.
   - **Exit codes**: changes.
   - **Report**: keys added, deprecated, removed; `schemaVersion` (stays 1).
   - **Configuration**: keys and files added or changed; `.swift-analyzers.json`.
   - **Cache**: location, format, what to delete on a runner, budget.
   - **Findings that may appear** and **findings that may disappear**: by rule, each with its probe and an example.
   - **Consumer steps**: maintastic (from 0032) and the g-cqd scripts and workflows (from 0031), as commands and file edits.
4. Before tagging: run the consumer steps on a branch of maintastic and of AemiJSON; both green, and the finding deltas
   match the note's two findings sections. Record the run in this repository's diary.
5. After tagging: open the consumer pull requests (0031, 0032) the same day.

Red: a release-note lint (sections present, each filled or "none", checksums match the published `.sha256`) run in the
tools' release workflow; it fails on today's free-form notes.

Acceptance: three waves shipped; every consumer on wave 3.
