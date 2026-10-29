---
status: accepted
date: 2026-10-29
---

# 0023 — Source discovery descends no link

## Context

`SourceDiscovery` followed a link inside the walked directory, to a directory or a file, and kept a visited set by device
and inode so a directory reached twice was listed once. Which spelling a file got depended on which name the walk met
first; a link to a file listed the file twice, once per name; and exclusion was matched against that spelling, so excluding
`Sources/` left `Sources` analyzed under an alias. On the parallel walker (ADR-0022, aemi ADR 0017), the first spelling
reached would also depend on timing.

## Decision

No link is descended. A link whose target resolves inside the walked directory stands for that target, which the walk
reaches at its own path; a link whose target resolves outside is dropped, as before; a dangling link the filter accepts is
listed, as before, so the analyzer reports it degraded. Exclusion therefore follows the real location: a directory excluded
is excluded under every alias, and an alias named like an exclude pattern cannot hide its target.

## Consequences

- Every file is listed once, under its real name, whatever the order of the walk. File lists are unchanged on trees
  without links (maintastic, the analyzer repositories, aemi, swift-syntax: 4,704 files and 34 manifests, diary
  2026-10-29-19).
- A link to something the walk skips (a hidden directory, `.build`, an excluded directory) no longer brings it in.
- Each candidate link costs one `stat`, to tell a dangling link from one that leads out.
