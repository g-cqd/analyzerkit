---
status: done
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
is a superset of swift-search's in what it records apart from three things: the name's position, the later components of a member type
(2,030 references on maintastic), and macro declarations (6). Time is equal (55.5 s against 54.4 s on maintastic,
debug, one thread, parsing included), and deadwood's peak memory is 45% higher.

analyzerkit `8215e78` (red `9eef461`): `SymbolFacts`, deadwood's collectors with the three additions
(`Declaration.nameLocation`, `Reference.nameLocation` on a member type's later components, `DeclarationKind.macro`)
and an AemiProtobuf payload whose messages (`SymbolFactsWire`) keep deadwood's field numbers, so its compact
references read as full ones. 7 tests, one comparing every row with deadwood's on a 43-line fixture.

deadwood `d25590b` (red `eef9c90`) collects through it and drops its copies, the JSON cache coding and AemiJSON from
its core. It leaves the macro declarations out, as before. Byte-equal to `ce84744`, stderr included: maintastic with
the Xcode store (56,642 bytes) and without (38,738), and deadwood's own Sources. A warm cache reports as a cold one
apart from the hit counters. The cache is 1.9% larger (35,820 KB to 36,488 KB on maintastic): the name locations.

swift-search's switch is roadmap 0061: the comparison found more differences than the three above once its output
was read field by field.
