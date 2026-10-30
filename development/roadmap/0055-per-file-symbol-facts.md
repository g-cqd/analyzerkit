---
status: not-started
blocked-by: []
date: 2026-10-30
---

# 0055 — Per-file symbol facts (P1, P2)

ADR-0027. swift-search's `SymbolExtractor` (declarations with kind, access, signature and container chain; references)
and deadwood's `DeclarationCollector` and `ReferenceCollector` come from the same SwiftStaticAnalysis code and have
diverged. Measure first (swift-search 0002): run both on a pinned g-cqd package and on maintastic, list every
declaration and reference one records and the other does not, with the reason, and the time and allocations of each.

Then, if one extraction serves both: `SymbolFacts` in analyzerkit, cached by `CorpusScanner` like the other per-file
facts (AemiProtobuf payload), with swift-search and deadwood switching in separate entries and their reports
byte-equal. If the differences are real requirements, this entry closes with the comparison and nothing moves.
