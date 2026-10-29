---
status: accepted
date: 2026-10-29
---

# 0008 — One path filter: a substring unless the entry is a glob

## Context

arcleak, dolly and fcheck exclude a path when it *contains* an entry; deadwood does the same unless the entry has `*` or
`?`, in which case it compiles a glob to a Swift `Regex` behind a cache and an antipattern guard. So `"Package.swift"`
excludes `MyPackage.swift` everywhere, and the same configuration selects different files per tool: on maintastic modeler
reads 2,973 files, fcheck 2,584, dolly 2,873, arcleak 2,830.

## Decision

1. One `PathFilter` in `SourceCorpus`, used by every tool for configuration `exclude`, `--exclude-path` and test globs.
2. An entry without glob metacharacters (`*`, `?`, `[`) keeps today's substring meaning, so no existing configuration
   changes meaning. An entry with them is a glob: `*` within a component, `**` across components, `?`, `[…]`, matched
   against the path relative to the project root, with a leading `/` anchoring at the root.
3. The matcher is a direct glob matcher over UTF-8 bytes, not a regular expression; directories are pruned during the
   walk when an entry excludes them.

## Consequences

- deadwood's `GlobMatcher`, `SafeRegex` and `RegexCache` are removed.
- Every tool analyses the same files for the same configuration; a golden test counts them on one fixture tree.
- A user who wants a regular expression does not get one here; if a later option needs one, it uses AemiRegex's
  linear-time engine (ADR-0012's sibling decisions apply).
