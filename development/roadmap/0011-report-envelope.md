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

## Progress

Diary 2026-10-29-14. Decided first: ADR-0017 supersedes ADR-0009 (`b492351`); the added keys would have retyped deadwood's
`notes` and fcheck's `tool`/`version`. Goldens: each of arcleak, deadwood, dolly and fcheck records JSON, SARIF, xcode,
baseline and exit codes on its fixture corpus plus `Goldens/Corpus` (a non-UTF-8 file stored as `.swift.bytes`), run on a
copy in a fresh repository root; red commits `4c891ce`, `d5942a3`, `24249bb`, `560c21b`. Recording them found 0044 (fcheck
SARIF locations absolute), fixed before its golden was recorded.

Envelope done: analyzerkit `f5c6619` red, `c260aa1` green (`ReportEnvelope`, `RunNote` with the ten-path cap, `SkippedFile`,
`ReportSummary.notChecked`). Adopted by arcleak `86b5d91`, deadwood `c5100b9`, dolly `3281adb`, fcheck `9085fb6`: SARIF,
xcode and baseline byte-identical to the goldens, JSON equal apart from the added keys, maintastic's decoder shape green.
Full suites: arcleak 219, deadwood 377, dolly 202, fcheck 82.

Remaining: the shared SARIF model, xcode lines, baseline codec and path presentation in `ReportSupport`, each tool's copy
deleted, under the same goldens; `--verbose` lifting the ten-path cap arrives with the shared options of 0013.
