---
status: not-started
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
