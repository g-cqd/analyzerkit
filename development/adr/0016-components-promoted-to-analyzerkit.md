---
status: accepted
date: 2026-10-29
---

# 0016 — What moves into analyzerkit, and what does not

## Context

Measured similarity between the tools' copies (research `2026-10-29-surface-and-duplication.md`): `SuppressionTable` 100 %,
`DirectiveScanner` 98 %, `SuppressionDirective` 84–88 %, `ReportFormatter` 85–89 %, `Baseline` 86–92 %, `PathPresentation`
54–84 %, `AnalysisReport` 69–90 %, the embedding providers 41–80 %, the facts caches 23–48 % against analyzerkit's own
`CorpusScan.FactsCache`. Some promotion already happened (`Severity`, the bounded reader).

## Decision

| Component | Into | Consumers |
| --- | --- | --- |
| `ProjectLayout`, toolchain resolution | `ProjectModel` | all |
| `IndexStoreSupport` | new product | arcleak, deadwood |
| `AnalyzerCLI` (option groups, stderr, exit codes, timings) | new target | all |
| `PathFilter`, discovery over Aemi's walker | `SourceCorpus` | all |
| report envelope, xcode/JSON/SARIF formatter, baseline, path presentation | `ReportSupport` | all |
| suppression (table, directive grammar parameterised by prefix, byte pre-filter) | new `Suppression` target | all |
| cache v2 | `CorpusScan` | all (arcleak, deadwood, dolly leave their own caches) |
| semantic embedding providers | new `SemanticEmbedding` target beside `WordPiece` | arcleak, deadwood, dolly |
| `ControlFlow` | stays; modeler adopts it | fcheck, modeler |

Not moved: deadwood's and dolly's parallel graph primitives (two consumers, tuned apart); each tool's rules, facts,
configuration types and `ToolInfo`. `FNV1a` copies are replaced by AemiKernel's `XXH64` where they fingerprint.

## Consequences

- Each move is a roadmap entry that first lands the component with its own tests, then migrates the tools with byte-equal
  reports (wave 1).
