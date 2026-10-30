---
status: accepted
date: 2026-10-30
---

# 0027 — What swift-search gives the family, and what it keeps

## Context

swift-search (local, `g-cqd/swift-search` `c245e45`) was extracted from SwiftStaticAnalysis's `SymbolLookup` on
analyzerkit `84c9a33` (its diary 2026-10-29-01). Its extraction report proposed thirteen promotions (P1–P13). By the
rule in "Where code lives", a component moves to the lowest package where a second consumer is plausible, and only with
an ADR naming the consumers. This ADR gives each proposal a verdict, from what the consumers do today (grep of every
tool's `Sources`, 2026-10-30), not from what they might do.

## Decision

| | Proposal | Verdict | Where | Consumers | Entry |
| --- | --- | --- | --- | --- | --- |
| P1 | per-file symbol facts (`SymbolExtractor`, `FileSymbols`, `Declaration`, `Reference`) | accepted once measured | analyzerkit | swift-search, deadwood (same lineage as its collectors) | 0055 |
| P2 | declaration kinds, access, signatures | with P1 | analyzerkit | the same | 0055 |
| P3 | JSON-RPC framing and connections | **done** | AemiJSON `AemiJSONRPC` (its 0006, `089781e`) | swift-search, arcleak `LspServer.swift`, ask `AskMCP`, Atelier | — |
| P4 | UTF-8 ↔ UTF-16 columns | accepted | analyzerkit `SourceCorpus` | swift-search (LSP), arcleak (LSP server), SARIF writers (`columnKind` defaults to UTF-16) | 0051 |
| P5 | finding the toolchain's `sourcekit-lsp` | accepted | analyzerkit `ToolchainResolution` | swift-search; any tool that asks sourcekit-lsp | 0052 |
| P6 | `BoundedProcess.withSession` (a long-lived child, process group killed at scope exit) | **deferred** | stays in swift-search | swift-search only; no analyzer runs an interactive child | — (trigger below) |
| P7 | `IndexQueries` (definitions of a file, references of a USR, `childOf`) | accepted after the index entries | analyzerkit `IndexStoreSupport` | swift-search, arcleak, deadwood | 0054 |
| P8 | freshness decided once per file per session | accepted | analyzerkit `IndexStoreSupport` | every index user (swift-search H3: N+1 `isCurrent`) | 0053 |
| P9 | linear-time patterns | **no promotion**: AemiRegex is already linear and `Sendable`, its 0015 made whole matches exact | — | deadwood deletes `SafeRegex`, `RegexCache`, `GlobMatcher` in 0019 | 0019 |
| P10 | the query language (`Type.member`, `name(label:)`, generics) | **refused** | stays in swift-search | swift-search only | — |
| P11 | `SourcePath.absolute` (against the working directory, then canonical) | accepted | analyzerkit `SourceCorpus` | all six: every tool builds it from `currentDirectoryPath`; arcleak's index path does it without canonicalizing | 0050 |
| P12 | exit statuses of a search | accepted | ADR-0026, `AnalyzerCLI` | swift-search | 0056 |
| P13 | doc-comment parser | **refused** | stays in swift-search | swift-search only; no tool parses doc comments | — |

Every accepted promotion: tests first in analyzerkit, the consumer's own tests unchanged, and its reports byte-equal
before and after the switch.

The owner decisions of the report, taken by their defaults and recorded here:

| | Decision |
| --- | --- |
| D1 | swift-search is a tool of its own, not a modeler subcommand (its ADR-0002) |
| D2 | one MCP server per tool; a family server is swift-search 0003, not before two tools serve MCP |
| D3 | nothing moves without an ADR naming its consumers (this one) |
| D4 | indexstore-db: one revision spelled the same everywhere (ADR-0025), not O1 |
| D5 | swift-search keeps 0 / 1 for match / no match (ADR-0026) |
| D6 | SwiftStaticAnalysis is left as it is |
| D7 | swift-search stays local until it has adopted analyzerkit's head and AemiJSONRPC |

## Consequences

- P6, P10 and P13 are revisited only when a second consumer appears; the report's code stays in swift-search. P6's
  trigger: a second analyzer running an interactive child. The session (its own process group, SIGTERM then SIGKILL
  after 2 s at scope exit, stdin and stdout as async byte streams feeding `AemiJSONRPC`) then moves beside
  `BoundedProcess`, with swift-search's tests first.
- The four defects swift-search found in its own lineage (`/private/var` against `/var`, exact names missing
  `name(label:)`, CRLF split as one `Character`, a dead public property) are probed in deadwood and arcleak, which share
  that lineage (0057).
- swift-search joins the benchmarks and budgets of 0029.
