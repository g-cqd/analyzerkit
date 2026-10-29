---
status: done
blocked-by: []
date: 2026-10-29
---

# 0007 — `SourceDiscovery` on the walker, streaming into the scan

Scope (K5): `SourceDiscovery` becomes a policy over `AemiFileSystem.DirectoryWalk` (aemi ADR 0017) (skip `.build`, `.git`, `DerivedData`, `.swiftpm`,
`checkouts`, hidden entries; `PathFilter` pruning); `CorpusScanner` consumes the batch sequence so reading and parsing start
before the walk ends.

Red: the counting seam (no stat per regular file); identical file lists to today's on golden trees.

Acceptance: dolly's and arcleak's main-thread discovery share drops on maintastic (measured before and after, median of
five, quiet machine).

Also: `ProjectLayout`'s ancestor lookup lists each ancestor with `FileManager.contentsOfDirectory`, 22.9 s on a
267,000-entry directory against 134 ms with `readdir` (aemi's diary 2026-10-29-02); its container check moves onto the
walker's listing too.

## Done

Diary 2026-10-29-19. aemi `8d91432`/`04e49d1` (red, green): `Policy.maxDepth`, so an ancestor is listed one level deep.
AemiJSON `9a7d445` pins the same aemi. analyzerkit `05197a0` red, `3032271` green: `SourceDiscovery` is a policy over
`DirectoryWalk` (four workers, the skipped names, hidden entries, exclusion pruning before entering), with
`discover(under:isExcluded:)` reporting unreadable directories and stat calls; links per ADR-0023; the predicates are now
`@Sendable`, since the walk calls them from its workers. `ProjectLayout.markers(in:)` lists each ancestor without opening
a subdirectory or stat'ing anything.

Red seen failing for each new test; one expectation was wrong and was corrected to today's behaviour: a link named like
an `.xcodeproj` never counted as a container (`attributesOfItem` does not follow a final link), so it still does not.

Identical file lists: dumped before and after on maintastic, the six analyzer repositories, aemi and swift-syntax (4,704
Swift files, 34 manifests): no difference. maintastic has no links; the unit tests cover them.

Measured (median of seven, warm cache, load about 3, old and new binaries alternated, JSON output byte-identical):

| maintastic | before | after |
|---|---|---|
| `SourceDiscovery.swiftFiles` alone | 232 ms | 24 ms |
| `arcleak analyze .` | 752 ms | 368 ms |
| `dolly analyze .` | 893 ms | 703 ms |

`ProjectLayoutTests`, whose fixtures sit in the 267,000-entry temporary directory with no repository above them: 15.0 s
to 1.0 s.

Tools: arcleak `32c15ea` (its `ProjectFileDiscovery` takes a `@Sendable` predicate), deadwood `4fbb624`, dolly `7e82e0a`,
fcheck `65d16c7`, modeler `a271b20`; suites green (229, 387, 211, 92, 63).

Not built: `CorpusScanner` consuming the walk's batches. With discovery at 24 ms of a 368 ms arcleak run, overlapping it
with reading and parsing saves at most that, and would change every tool's scan entry point. Revisit if a profile shows
discovery on the critical path of a larger tree; the walker's `batches` API is there for it.

Left over: no tool reports an unreadable directory yet (0046).
