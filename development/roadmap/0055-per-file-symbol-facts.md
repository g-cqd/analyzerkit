---
status: in-progress
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

## Progress

The measurement is done (research 2026-10-31-per-file-symbol-facts-compared). One extraction serves both. deadwood's
is a superset of swift-search's apart from three things: the name's position, the later components of a member type
(2,030 references on maintastic), and macro declarations (6). Time is equal (55.5 s against 54.4 s on maintastic,
debug, one thread, parsing included), and deadwood's peak memory is 45% higher.

Next: `SymbolFacts` in analyzerkit, deadwood's collectors with those three additions, cached through `CorpusScanner`
with an AemiProtobuf payload. Then deadwood and swift-search switch, each in an entry of its own, with byte-equal
reports.
