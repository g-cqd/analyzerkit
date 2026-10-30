---
status: accepted
date: 2026-10-30
---

# 0026 — A search exits 1 when nothing matched (amends ADR-0018)

## Context

ADR-0018 gives the statuses of an *analysing* command: 1 means a finding fails the run. swift-search's `find` and
`usages` are not analyses: they answer a question, and their callers (scripts, agents through a shell) need to know
whether there was an answer, the way they do with `grep` and `git grep`. swift-search exits 0 when something matched and
1 when nothing did, and uses ADR-0018's 64, 70 and 74 for the rest (`SwiftSearchCommand.swift`). Under ADR-0018 as
written, 1 would mean "a finding of severity error", which a search has none of.

## Decision

1. A **search command** (one that prints matches and no findings): 0 when at least one match was printed, 1 when the
   search ran and nothing matched. 64, 70, 74 and 78 keep ADR-0018's meanings; 2 is not used.
2. `--strict` does not apply to a search. A search never prints a report of findings, so ADR-0018's rule on reports
   does not apply either; nothing matched prints nothing on standard output and a one-line note on standard error.
3. `AnalyzerCLI.ExitStatus` gains `noMatch` (1), documented as the search status, beside `findings` (1).
4. An MCP tool never exits: no match is an empty result, not an error (`isError: false`).

## Consequences

- swift-search keeps its statuses (its decision D5) and takes `ExitStatus.noMatch` from analyzerkit when it bumps.
- A tool that adds a search subcommand later follows this, not ADR-0018's table.
- Roadmap 0056 is the analyzerkit change: the case, its documentation, a golden of the status table.
