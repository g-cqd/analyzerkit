---
status: accepted
date: 2026-10-30
---

# 0028 — `--report-new-since` is decided in analyzerkit

## Context

ADR-0019 puts `--report-new-since <baseline file>` in the shared Output group, so every tool's analysing command
offers it once it migrates (roadmap 0018–0022). Only deadwood implements it (`NewFindings`: promote the out-of-scope
findings the base branch's baseline lacks, flag a baseline that matches nothing, and two notes). Each tool would write
the same twenty lines over its own finding type.

## Decision

`ProjectModel.NewSince`, beside `ReportScope`: `promote(inScope:outOfScope:notIn:fingerprint:)`,
`matchesNothing(_:in:fingerprint:)` and `notes(promoted:matchesNothing:baseline:)`, generic over the finding type with
the fingerprint given as a function. The messages are deadwood's, word for word, so its reports do not change. Each
tool keeps the order of its own steps (read the baseline before the analysis so a bad path fails with 78; promote before
`--baseline`; count the promoted after it), and the rule that the option requires `--only` or `--only-from`.

Consumers: deadwood (replaces `NewFindings`), arcleak, dolly, fcheck, modeler, as each migrates.

## Consequences

- deadwood's `NewFindings` and its tests go in 0019; its `--report-new-since` output stays byte-equal.
- The other four gain the option with the same semantics and notes.
