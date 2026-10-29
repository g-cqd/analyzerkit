---
status: done
blocked-by: []
date: 2026-10-29
---

# 0003 — Control flow: catch-all bindings, `for try await`, `fallthrough`, labelled `break`

Scope (K1–K3): a `catch` clause whose items are only a binding pattern (`catch let error`, `catch _`) and no `where` is
catch-all; `ForStmtSyntax.tryKeyword` adds a throw edge from the loop header; `fallthrough` jumps to the first statement of
the next case; `break label` out of a labelled `do` or `if` reaches the statement after it (labels on any statement).

Red: `research/probes/ControlFlowProbes.swift` as assertions; fcheck's `fcheck-probes.sh` K1 and K2 as fcheck tests once
the dependency moves.

Acceptance: the four probes give the expected graphs; fcheck K1 reports nothing and never "line 0", K2 reports the leak.

## Done

Diary 2026-10-29-06. Red `f517125` (seven tests, twelve issues), green in the next commit. fcheck against this tree (local
`swift package edit`): K1 0 findings, K2 the `for try await` leak; fcheck's suite green; its findings on maintastic,
AemiProtobuf, aemi and ask identical before and after (1, 0, 0, 12). fcheck still pins the previous analyzerkit; moving
the pin is part of 0035.
