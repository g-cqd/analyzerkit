---
status: done
blocked-by: []
date: 2026-10-29
---

# 0008 — `ProjectLayout`: SwiftPM, Xcode, workspaces, nested packages, worktrees

Scope (ADR-0003): root from the analyzed paths; containers and packages listed; DerivedData matched by `WorkspacePath`
(newest first) and `-derivedDataPath` roots accepted. Project-derived test, generated and script classification is split
into 0043; it needs target/product parsing, not just filesystem layout. Xcode builds remain in 0033.

Red: fixtures — a package; an Xcode project with nested local packages (maintastic's shape); a workspace; two worktrees
of one project with two DerivedData folders; a `-derivedDataPath` build. Today's tools pick the nested package as root and
miss the worktree's DerivedData (A5, D6).

Acceptance: every fixture resolves; on maintastic the worktree's own DerivedData is found from the repository root and from
`ShareAPI/Sources`.

## Done

Diary 2026-10-29-11. `ProjectModel.ProjectLayout` depends on SourceCorpus, without a dependency cycle. Root comes from
the common directory of canonical input paths, walking to the repository boundary (.git directory or worktree file):
outermost ancestor with an Xcode container, else outermost package, else repository root, else common directory.
Lists manifests and containers via SourceDiscovery, excluding private workspaces embedded in projects.

Red `46fe5b7`, green `42136ca`; oversized metadata red `620052a`, bounded-read green `c17fd4e`; FoundationEssentials
where available `11a71af`. Seven fixture tests: packages, nested packages, workspaces, worktrees, custom build roots,
canonical/symlink paths, metadata dates and mtime fallback, malformed/missing metadata, and the 1 MiB cap. Directly
supplied build roots can omit metadata; discovered children cannot. Metadata, when present, must always match.

Arcleak `43dd13c` red, `e7b6dec` green; deadwood `178f468` red, `1e57190` green. Both pin `11a71af` and replace
folder-name matching with the shared discovery, retaining their existing SwiftPM candidate order and population checks.
Arcleak resolves from CLI inputs rather than the first analyzed file; deadwood's root seam uses all analyzed paths.
Full suites: arcleak 208 tests, deadwood 366; repinned dependency and maintastic probe tests green after the full runs.

Read-only maintastic probes in all three repositories: root and ShareAPI/Sources produce the same worktree root, 17
packages, one Xcode project, and only Oculavis_Share_IOS-fygsyifvnhrizrfdclbpemklqblj/Index.noindex/DataStore. Both
tools' default path finders return that exact store from either starting directory. No consumer files or stores modified;
these are discovery checks, not an end-to-end index correctness claim. Linux and CI fixes remain deferred.
