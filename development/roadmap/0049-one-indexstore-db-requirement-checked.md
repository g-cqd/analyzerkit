---
status: done
blocked-by: []
date: 2026-10-30
---

# 0049 — Check that every package spells indexstore-db the same

ADR-0025. A script, `Scripts/family-pins.sh`, given the directory holding the checkouts, prints each package's
requirement on indexstore-db, aemi, AemiRegex, AemiJSON, AemiProtobuf and analyzerkit as written in its `Package.swift`,
and exits 1 when two packages write one identity differently. It reads manifests as text; it resolves nothing.

Red: a fixture directory of three manifests, one with `branch: "release/6.4.x"` against two revisions, makes it exit 1
and name the package; the same fixture with identical revisions exits 0.

Today it would report: indexstore-db `0390867` (analyzerkit, swift-search) against `64aa0b2` (arcleak, deadwood); aemi
`2fbe4e4` (AemiRegex, MacFS) against `04e49d1` (AemiJSON). Neither conflicts yet, because no package depends on both
sides; the script is there for the day one does. Not a CI job until the CI work resumes.

## Done

`Scripts/family-pins.sh <dir> [package ...]` (POSIX `sh` and `awk`; runs under sh, bash and zsh): every `url:`
requirement of every manifest under the directory, or of the packages named; exit 1 when an identity has two spellings
and one of them is a revision or a branch, listing each spelling with its packages; then the table of revision and
branch requirements. 4 tests (`FamilyPinsTests`, fixture manifests), red at the commit before this one.

Two findings while writing it:

- A root package's own requirement does not settle a conflict between two of its dependencies: probe C6 (the root
  requiring indexstore-db `0390867` above one dependency at that revision and one on `release/6.4.x`) fails with the
  same message. ADR-0025 holds as written.
- The script reads working-tree manifests, so it answers "would the next train resolve", not "does today's graph":
  analyzerkit resolves today although AemiProtobuf's head requires AemiJSON `fdc0143` and analyzerkit `9a7d445`, because
  the AemiProtobuf revision analyzerkit pins (`b11dc91`) does not depend on AemiJSON yet.

Its report on the family (2026-10-30, `aemi AemiJSON AemiRegex AemiProtobuf analyzerkit arcleak deadwood dolly fcheck
modeler swift-search`), the next train's work:

| Identity | Spellings | Who |
| --- | --- | --- |
| aemi | `04e49d1` / `2fbe4e4` | AemiProtobuf, analyzerkit, swift-search / AemiJSON, AemiRegex |
| AemiJSON | `fdc0143` / `9a7d445` | AemiProtobuf / analyzerkit and the five tools, swift-search |
| AemiRegex | `fe9b07f` / `d5bac1c` | swift-search / AemiJSON |
| indexstore-db | `0390867` / `64aa0b2` | analyzerkit, swift-search / arcleak, deadwood (ADR-0025; 0018, 0019) |
| analyzerkit | `84c9a33` / `3032271` | swift-search / the five tools (never in one graph) |

Order that clears it: AemiProtobuf to aemi `2fbe4e4` and AemiJSON's head; analyzerkit to aemi `2fbe4e4`, AemiJSON's and
AemiProtobuf's heads; swift-search to analyzerkit's head with the same three; the tools in their migrations.
