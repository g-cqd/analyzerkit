---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0047 — `AemiInterner` in every consumer

Found when 0015 closed: the interner exists and measured five times the dictionary on USRs and 2.5 times on tokens, but
nothing uses it. Where each consumer moves, and what it must show:

| consumer | tables | where | gate |
|---|---|---|---|
| deadwood | USRs: declarations, references, the index graph (35 `String`-keyed tables in the sources) | 0024 | index run on maintastic faster, findings identical |
| dolly | per-file token tables and `CorpusAssembler` | 0027 | closed: identical outputs, but assembly 15.9 against 13.8 ms; not adopted (0027) |
| arcleak | type and member names, the ownership graph | 0023 | findings identical; graph build faster |
| modeler | `ModelFacts`' name index, reentrancy bookkeeping | here | measure first; adopt only on a gain in a real run |
| fcheck | rule tables (static, small) | here | measure first; likely no change |
| analyzerkit | rule identifiers in `SuppressionTable`, `CorpusScan`'s per-file facts | here | measure first |
| AemiJSON | object keys while decoding | AemiJSON roadmap | measure first (ADR-0012's second consumer) |
| AemiProtobuf | descriptor and field names | AemiProtobuf roadmap | measure first |

Common to all: keys are interned from bytes the consumer already holds, never from a `String` made for the purpose;
symbols are compared and hashed, and text is resolved only to print; a parallel phase interns per task and merges with
`Interner.merge`, which keeps symbols deterministic, so outputs and goldens do not change.

Open, decided by the first two migrations (deadwood, dolly): whether `Interner.intern` becomes `@inlinable`. A call into
another module costs 15 to 20% in aemi's micro-benchmark (aemi's diary 2026-10-29-03); it matters only if a real run's
profile shows interning on the critical path, and making it inlinable exposes the table's layout to every consumer.

Red, per consumer: its outputs on its goldens unchanged with the interner in place (the change is not observable except
in time), plus a benchmark or profile before and after on maintastic, median of five.

Acceptance: each row done or closed with its measurement.
