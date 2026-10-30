---
status: done
blocked-by: []
date: 2026-10-30
---

# 0050 — `SourcePath.absolute` (P11)

ADR-0027. `SourcePath.absolute(_ path:, in directory: = current)`: a relative path joined to the directory, then
`canonical`. Every tool does this by hand from `FileManager.default.currentDirectoryPath` (arcleak 5 sites, deadwood 4,
dolly 3, fcheck 2, modeler 1, swift-search's `SourcePath+Absolute.swift`); arcleak's index-store path joins without
canonicalizing, which is the `/private/var` against `/var` defect swift-search found (0058).

Red: a relative path, `.`, `..`, an absolute path, and a path under a symbolic link (`/var` → `/private/var` on macOS),
each against a given directory, give the canonical absolute path; the current-directory default equals passing it.

Acceptance: swift-search deletes its extension when it bumps; each tool switches in its migration (0018–0022), reports
byte-equal.

## Done

`SourcePath.absolute(_:in:)` and `absolute(_:)` (the current directory) in `SourceCorpus`: an absolute path ignores the
directory, an empty one is the directory, a relative one is joined, then `canonical`. A tilde stays a name. 6 tests
(`SourcePathAbsoluteTests`), red at `7631a50`; a directory spelled through a link gives the resolved spelling, which is
the `/var` against `/private/var` case on macOS. `SharedConfiguration` drops its private copy for it.

Found on the way: `canonical` alone already resolves a relative path against the current directory (`URL(fileURLWithPath:)`
does), so swift-search's extension was a second spelling of `canonical`; what the tools lacked was a directory other than
the current one (configuration files, a store path relative to the project). The tools switch in 0018–0022; swift-search
in its 0006.
