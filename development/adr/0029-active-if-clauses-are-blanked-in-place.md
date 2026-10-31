---
status: accepted
date: 2026-10-31
---

# 0029 — Under `--define`, inactive `#if` clauses are blanked in place

## Context

ADR-0019 gives every tool `--define`, and the shared configuration has `defines` and `platforms` (ADR-0020). arcleak
builds a `StaticBuildConfiguration` from them and walks only the active clauses (`activeClause(in:)` in its two
visitors). fcheck and modeler read every clause and said `--define` had no effect (roadmap 0021, 0022). Their analyses
walk syntax with many visitors, and fcheck's also runs analyzerkit's `ControlFlowGraph` builder. Teaching each of
them, the graph builder included, to skip inactive clauses would touch every walk, and a walk that missed it would
read the wrong code without a sign.

SwiftIfConfig's `removingInactive(in:)` rewrites the tree without the inactive code, but it moves every line after
the first removed clause, so reports, suppressions (by line) and SARIF regions would shift.

## Decision

`ProjectModel.CompilationConditions(defines:platforms:)` holds arcleak's recipe for the build configuration (custom
conditions, Swift 6, compiler 6.4, the `os()` of the platforms or the host's), and `activeSource(_:tree:)`. That call
replaces the elements of every inactive clause, outside any other inactive clause, with spaces, keeping line breaks,
and returns nil when no clause is inactive. A tool parses the result again and walks it as before: every byte keeps
its offset, so lines, columns and fingerprints of the code that stays do not move, and the `#if` lines themselves stay.

- Asked only with a define (`isRequested`). Without one every clause is read, as before, so no finding moves for a
  run that does not ask.
- The defines and platforms are in each tool's cache salt.
- Adopted by fcheck and modeler (roadmap 0059). arcleak keeps walking active clauses with its visitors, and builds
  its configuration through `CompilationConditions.buildConfiguration`, so the three tools read one recipe.
- deadwood and dolly keep reading every clause, by design: a declaration used only under another configuration is not
  dead, and clones compare the tokens of every clause.

## Consequences

A run with a define parses each file twice when the file has an inactive clause; files without `#if` parse once.
`canImport` is not modelled, as in arcleak.
