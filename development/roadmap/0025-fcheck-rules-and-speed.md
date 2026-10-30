---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0025 — fcheck: rule fixes and the quadratic callee (wave 2, speed in wave 1)

Repository: g-cqd/fcheck. Scope: `CallSite.last` and `callee` from tokens (`DeclReferenceExprSyntax.baseName`,
`MemberAccessExprSyntax.declName`), computed once, `nil` callee for shapes that are not a dotted name (F7, wave 1); acquirers
to a fixed point, implicit returns included, pass 2 parallel and cached, files selected by identifier tokens, not substrings
(F1, F1b); reassignment of a held handle reported (F2); prefixes matched at a camel-case boundary (F3); corpus acquirers
matched with arity and base type when known (F4); flushes typed by target, directory flush recognised by its descriptor's
origin, `flush` substring dropped (F5); the throw line from the throwing node (F6).

Red: `fcheck-probes.sh` cases as tests; a scaling test on a 2,000- and a 4,000-deep SwiftUI-like chain (time ratio ≤ 2.5;
today ≈ 4).

Acceptance: tests; cold CPU on maintastic measured before (7.9 s user) and after; new and vanished findings on the g-cqd
packages listed in the release note.
