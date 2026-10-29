---
status: in-progress
blocked-by: []
date: 2026-10-29
---

# 0035 — Wave 0: patch releases for defects that make a gate wrong

Scope (ADR-0015 item 4): before the foundations, the smallest fixes for defects that produce wrong gate results today, each
red first, released as patches with the standard note:

- arcleak 0.12.1: never look up a name the corpus declares (A2); never infer class-ness when the declaring file no longer
  declares the type (A4, error severity today); never create `v5/` or `IndexDatabase/` in a path that is not a store (A6).
  arcleak gates the reference app.
- deadwood 0.11.2: accept a user-owned `Xcode.app` dylib under the same policy as arcleak (D4); no writes in a path that is
  not a store (D1).
- fcheck 0.1.2: K1 and K2 through analyzerkit 0003; the token-based callee (F7) as a pure speed fix.

Red: the corresponding probes (`ArcleakFakeIndexProbe.swift`, `index-fixtures.sh` A4/A6/D1, `TrustProbe.swift`,
`fcheck-probes.sh` K1/K2).

Acceptance: patches published; the reference app and the g-cqd lock bumped (one line each, 0031, 0032); no other finding changes on
the golden corpora.

## Progress

Code done, red then green, pushed to each `main` (diary 2026-10-29-08): fcheck `7384041`…`7772bef` (K1, K2 through the
analyzerkit pin; F7), arcleak `cd25c6c`…`c36b2f4` (A2 in both its forms, A4, A6), deadwood `01351b8`…`c8fbbc0` (D4, D1).
Release notes drafted (research `2026-10-29-wave-0-release-notes.md`). Not done: tagging the three releases, and the
consumer bumps, which wait for the owner and a reference app branch run (ADR-0015 item 5).
