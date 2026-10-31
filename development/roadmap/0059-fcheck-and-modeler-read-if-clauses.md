---
status: done
blocked-by: []
date: 2026-10-30
---

# 0059 — `--define` in the tools that read every `#if` clause

ADR-0019 gives every tool `--define`. arcleak evaluates `#if` with SwiftIfConfig's `StaticBuildConfiguration` and walks
the active clauses only. fcheck (0021) reads every clause, so `--define` would change nothing; it says so on stderr.
modeler (0022) does the same, and says so too.

Do: with `--define` or `defines` given, walk only the clauses active under a configuration built as arcleak builds it
(the defines, the language and compiler versions, the host or configured platforms). Without either, keep reading every
clause, which is today's behaviour, so no finding moves for those who do not ask. If a second tool needs the same
configuration, it moves to analyzerkit, with an ADR naming arcleak and the tools that adopt it.

Red: a function leaking a handle inside `#if FEATURE` is reported without `--define`, and with `--define FEATURE`; it is
not reported with `--define OTHER` when an `#else` holds the closing version. Statement-level `#if` inside a function
body follows the same rule.

## Done

ADR-0029. The code that stays keeps every line and column.

- **analyzerkit** `1719d88` (red `19c71fc`): `ProjectModel.CompilationConditions`. It holds arcleak's
  build-configuration recipe and `activeSource(_:tree:)`, which blanks the inactive clauses' elements in place.
- **fcheck** `f2a1688`, `64aaf8e` (red `46e7dc6`) and **modeler** `ebe8712` (red `e534d70`):
  - With `--define` or `defines`, the file is parsed again from its active source.
  - `defines` and `platforms` are read and go into the cache salt (when set, so other salts do not move).
  - The "no effect" note is gone.
  - Without a define nothing changes.
- **arcleak** `2e7ab60` builds its configuration through `CompilationConditions`.
