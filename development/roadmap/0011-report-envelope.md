---
status: in-progress
blocked-by: []
date: 2026-10-29
---

# 0011 — The report envelope and the shared formatter, baseline and paths

Scope (ADR-0017, ADR-0016): `ReportSupport` gains the envelope (`tool`, `version`, `runNotes`, `skippedFiles`, `timings`), the
xcode/JSON/SARIF formatter, `Baseline`, `PathPresentation`; the summary line's "(N not checked)"; `--verbose` lifts the
ten-path cap.

Red: golden JSON, SARIF, xcode and baseline files from today's arcleak, deadwood, dolly and fcheck on their fixture
corpora (modeler has no report formatter; it adopts the shared one in 0022); the shared
formatter must reproduce them byte for byte apart from the added keys; a decode test with maintastic's
`StaticAnalysisReport` shape (schemaVersion and six finding keys) must pass on the new output.

Acceptance: goldens green; maintastic's decoder shape green.
