---
status: done
blocked-by: []
date: 2026-10-29
---

# 0008 — `ProjectLayout`: SwiftPM, Xcode, workspaces, nested packages, worktrees

Scope (ADR-0003): root from the analyzed paths; containers and packages listed; DerivedData matched by `WorkspacePath`
(newest first) and `-derivedDataPath` roots accepted. Project-derived test, generated and script classification is split
into 0043; it needs target/product parsing, not just filesystem layout. Xcode builds remain in 0033.

Red: fixtures — a package; an Xcode project with nested local packages (the reference app's shape); a workspace; two worktrees
of one project with two DerivedData folders; a `-derivedDataPath` build. Today's tools pick the nested package as root and
miss the worktree's DerivedData (A5, D6).

Acceptance: every fixture resolves; on the reference app the worktree's own DerivedData is found from the repository root and from
`API/Sources`.

## Done

Diary 2026-10-29-11. `ProjectModel.ProjectLayout` depends on SourceCorpus, without a dependency cycle. Root comes from
the common directory of canonical input paths, walking to the repository boundary (.git directory or worktree file):
outermost ancestor with an Xcode container, else outermost package, else repository root, else common directory.
Lists manifests and containers via SourceDiscovery, excluding private workspaces embedded in projects.

Red `1d6810b`, green `edb0a71`; oversized metadata red `df830ab`, bounded-read green `60d35c7`; FoundationEssentials
where available `5c6819f`. Seven fixture tests: packages, nested packages, workspaces, worktrees, custom build roots,
canonical/symlink paths, metadata dates and mtime fallback, malformed/missing metadata, and the 1 MiB cap. Directly
supplied build roots can omit metadata; discovered children cannot. Metadata, when present, must always match.

Arcleak `e1e4e63` red, `dd05e2f` green; deadwood `dbfc3b8` red, `3000614` green. Both pin `5c6819f` and replace
folder-name matching with the shared discovery, retaining their existing SwiftPM candidate order and population checks.
Arcleak resolves from CLI inputs rather than the first analyzed file; deadwood's root seam uses all analyzed paths.
Full suites: arcleak 208 tests, deadwood 366; repinned dependency and the reference app probe tests green after the full runs.

Read-only the reference app probes in all three repositories: root and API/Sources produce the same worktree root, 17
packages, one Xcode project, and only Example_App-fygsyifvnhrizrfdclbpemklqblj/Index.noindex/DataStore. Both
tools' default path finders return that exact store from either starting directory. No consumer files or stores modified;
these are discovery checks, not an end-to-end index correctness claim. Linux and CI fixes remain deferred.
