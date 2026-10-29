---
status: done
blocked-by: []
date: 2026-10-29
---

# 0012 — Shared suppression, with a byte pre-filter

Scope (ADR-0016): one `Suppression` target (table, directive grammar parameterised by the tool's prefixes, scanner); a
comment reaches the directive parser only if a byte scan (`CAemiKernels` `ByteSet`) finds `@` followed by a known prefix.
fcheck's own `Suppression.swift` folds in.

Red: the directive grammar tests of arcleak, deadwood and dolly run against the shared target; a counting seam shows the
parser is not called for comments without the marker (today `SuppressionDirective.parse` is ≈ 55 % of arcleak's parse time).

Acceptance: identical suppression results on the four tools' fixture corpora.

## Done

Diary 2026-10-29-13. New analyzerkit product `Suppression` (SwiftSyntax + AemiKernels): `DirectiveGrammar` parameterised
by namespaces and trimming, `Directive<Rule>`, `SuppressionTable<Rule>`, one source-accurate comment sweep. Red
`2037b9c` (grammar for the four prefix pairs, table precedence, CRLF/UTF-8/EOF offsets, and a counting seam: the
parser is called for 3 of 8 comments, only those with `@` + a known namespace), green `32cb93e`, vector-boundary and
partial-prefix tests `a9ed00e`. The marker scan is AemiKernels' `ByteSet` for `@` over borrowed UTF-8, then a prefix
compare; comments without it allocate nothing and never ask the converter for a line.

Each tool first got characterization tests of its own wire shape and precedence (arcleak `cb1bb82`, deadwood `db2ec9e`,
dolly `7956493`, fcheck `da45600`), green before and after. Then the adoption, pinning `32cb93e`: arcleak `d8f2dcb`,
deadwood `2ab71b7`, dolly `c402bb1`, fcheck `ee537f1`. Directive and table types stay tool-owned facades so caches and
JSON keep their shapes (Set rules vs fcheck's ordered array, Kind spellings); deadwood keeps horizontal-only trimming.

Identical results: a four-prefix golden corpus (regions, accepts, reasons; findings and suppressions in every tool) gives
byte-identical JSON and exit codes before and after in all four tools; the arcleak, deadwood and dolly fixture corpora
give byte-identical JSON against the previous release binaries (60, 30 and 20 files). Full suites: arcleak 213,
deadwood 371, dolly 196, fcheck 75, analyzerkit green.

Speed, release, interleaved, same tree, identical directives (probe `research/probes/SuppressionScanProbe.swift`, the
legacy code copied from arcleak `cb1bb82`): a 20,000-comment file with 20 directives scans in 0.0027 s median against
0.284 s (five rounds each). Not yet measured on maintastic end to end; that belongs to 0029's per-tool timings.
modeler has no suppression today; it adopts the shared grammar with its migration (0022).
