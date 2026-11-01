---
status: in-progress
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

## Progress

2026-11-01, steps 1 to 4 are in; step 5 has its entries (0068 to 0070) and is not started.

1. **Dead code.** dolly `cd576db`: what deadwood showed nothing reaches. Conservative: kept what the owner says is a surface.
2. **Wire mirrors.** analyzerkit has `Directive` coding, `Fingerprint` and `FindingBaseline` (ending at `c8ddcc4`); arcleak
   `e85e2ab`, deadwood `887e97c` and dolly `20b0768` deleted their mirrors. **`PathPresentation` stays in each tool.** The shared
   rule was already `PathPresenter`; what is left is which fields it applies to, and that differs on purpose: arcleak strips
   message and note text, dolly rewrites the related paths inside the note and moves `fingerprintAnchor`, deadwood strips a
   degraded file's detail and keeps `confidence`. A generic version would be a closure per field, longer than the three bodies.
3. **Embeddings (0028).** analyzerkit `a82ff6a`, target `SemanticEmbedding`; arcleak `8c085ad`, deadwood `e0025cb`, dolly
   `c61c7a2`. The experimental output (rank, confidence, `--semantic`) matched the previous builds byte for byte, with the real
   NLContextualEmbedding. Not run: the Hugging Face / Core ML provider against a real bundle (none at hand). Failure texts of
   the fallback paths were unified, and the Hugging Face provider reads the output dimension by name, deadwood's fix.
4. **Report layer.** analyzerkit `c1aa297` and `45f5093`: `ToolReport`, `ToolReportFormat` (xcode, JSON and SARIF renderers,
   the summary line, the run notes' order, skipped files by path) and `ReportOutputFormat`. arcleak `0a4e1d9`, deadwood
   `618b697`, dolly `096b896` conform to it. Cold and warm json, sarif and xcode, `--write-baseline` and `--baseline` matched
   the previous builds byte for byte on the fixtures and on the other two tools' `Sources`. **`AnalysisReport` stays in each
   tool**: its extra fields differ (deadwood's cache failure and notes, dolly's semantic and context notes), and `ToolReport`
   is the surface the renderers need. One behaviour moved: a run that analyzed nothing counts whole files skipped, each path
   once (deadwood's rule); arcleak and dolly counted degraded entries, so one file degraded twice could look like two.
   fcheck and modeler are not on it: fcheck has no SARIF and modeler's report is its own.

Not verified: a reference app corpus comparison (only the fixtures and the family's own sources), the SARIF related-location and
degraded-file paths on a real corpus beyond those, and the Linux build of the new commits.
