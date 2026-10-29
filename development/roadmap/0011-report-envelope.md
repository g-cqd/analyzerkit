---
status: done
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

## Done

Diary 2026-10-29-15. Shared in `ReportSupport`, each red then green, each adopted by the four tools under the goldens:
`Sarif` (one model, `197d68e`), `PathPresenter` and `BaselineFile` (`e13dab0`), `XcodeDiagnostic` (`0de4a5e`).
Tools' private copies deleted: SARIF structs, payloads, prefix helpers, line formatting (arcleak `2e02012`, `bc9234c`,
`f427051`; deadwood `5e4ef6d`, `1815294`, `b755c2b`; dolly `4338eae`, `356c5af`, `9c0e2ab`; fcheck `8941a1e`, `7afdbf9`,
`90e8385`). Each tool keeps what is its own: rule catalogue, degraded results, column policy, encoder, fingerprint, and
which fields pass through the presenter. Goldens byte-identical throughout; full suites green (219, 377, 202, 82).

One message changed: a baseline without `version` reads "the baseline has no version" in arcleak, deadwood and dolly
instead of a decoding error; exit code unchanged. fcheck now refuses a baseline whose version is not 1.

Deferred, explicitly: the `--verbose` flag that lifts `RunNote`'s ten-path cap is wired with the shared options (0013);
no tool lists note paths until the index notes of 0010. modeler, which has no report formatter, adopts all of this in
0022. Release binaries on maintastic not run in this entry.
