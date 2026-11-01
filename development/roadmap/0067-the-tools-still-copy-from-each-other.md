---
status: not-started
blocked-by: []
date: 2026-11-01
---

# 0067 — What the tools still copy from each other

The migrations (0018 to 0022) are done, and dolly still finds about 21,900 tokens of code in two or more tools. The evidence,
the groups and their order are in `2026-11-01-duplication-after-the-migrations.md`. Two ADR-0016 rows were never started
(0028, 0047); the rest is the per-tool layer over shared code: wire mirrors of shared types, the report types, the embedding
providers.

Red, per step: the shared piece lands with its own tests, and each tool's goldens and its report on the reference app stay
byte-equal after the tool moves onto it.

Steps, in order (the research note gives sizes and the reason for the order):

1. Delete what deadwood shows nothing reaches (dolly first); keep what the owner says is a surface.
2. Wire mirrors: `SuppressionDirective`, `Baseline`, `PathPresentation`. First test: arcleak's inline FNV and deadwood's
   `FNV1a` give the same fingerprint.
3. `SemanticEmbedding` (0028).
4. The report layer: a finding protocol, `ReportFormatter`, `AnalysisReport`.
5. Facts coding, the commands' run skeleton, configuration.

Acceptance: steps 1 to 4 shipped, every tool's reports and baselines unchanged, and the copies deleted; step 5 has its own
entries before it starts.
