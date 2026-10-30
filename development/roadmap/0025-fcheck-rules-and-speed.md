---
status: done
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

## Done

fcheck `d15edb3` (red `ca096a6`). F7 and the scaling test had landed earlier; F6 and K1/K2 already held.

- **F1:** acquirers reach a fixed point. Each round reruns the files whose calls (`FileResult.calledNames`, the
  calls' last names, not substrings) name a new acquirer. The rerun goes through `CorpusScanner`, in parallel and
  cached in a workspace of its own (`<workspace>#acquirers-<round>`), salted with the acquirers' digest, so a warm
  run reads every round from the cache.
- **F1b:** a body that is one acquiring expression returns its handle.
- **F2:** acquiring into a name that still holds a handle reports the first handle, "when it is reassigned at line
  N".
- **F3:** non-owning prefixes match at a camel-case boundary.
- **F4:** acquirers are recorded as `Type.name#required-total`. A call matches on its arity, and on its base's type
  when parameters, `let x: T`, `let x = T(...)`, `self` or a capitalised name give it (`TypeScope`).
- **F5:** flushes are typed. Any flush settles written bytes; only a directory flush settles a rename. A directory
  flush is `fsync`/`fdatasync`/`F_FULLFSYNC` on a descriptor opened with `O_DIRECTORY`, on a directory path, or
  named like a directory; `flush`/`sync` given or called on such a descriptor; a name with a flush word and a
  directory word; or a configured name. The "contains flush" rule is gone.
  - A first cut flagged ask's `flush(directory)` helper. That case is now a test.

Acceptance:

- `fcheck-probes.sh` gives every expected verdict.
- Cold CPU on maintastic (2,571 files, release, three rounds): 1.39 s user before, 1.51 s after. Wall time (0.45 s)
  and warm runs (0.25 s) are unchanged. The 7.9 s above predates F7.
- Release note: no new or vanished findings on maintastic or any g-cqd package, compared against `f58b04e`.
