---
status: not-started
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
