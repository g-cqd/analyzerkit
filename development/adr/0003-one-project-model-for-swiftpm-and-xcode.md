---
status: accepted
date: 2026-10-29
---

# 0003 — One project model for SwiftPM and Xcode

## Context

Each tool guesses the project root on its own. arcleak walks up from the *first analyzed file* to a `Package.swift`;
deadwood stops also at `.xcodeproj`; both then match DerivedData by the folder's name. On maintastic (an Xcode project in a
worktree named `parts-MAIN-24752-stock-handling`, with 17 nested local packages) both report "no index store found" while a
fresh DerivedData index of that exact worktree exists, and analysing `ShareAPI/Sources` moves the root into the nested
package (probes A5, D6). Two worktrees of one project have DerivedData folders with the same name prefix; only
`info.plist`'s `WorkspacePath` tells them apart. `--index-store-build` exists only for SwiftPM.

## Decision

`ProjectModel` gains `ProjectLayout`, used by every tool for every feature:

1. The root comes from the analyzed path arguments (their common directory), walking up to the first of `.xcworkspace`,
   `.xcodeproj`, `Package.swift` at the repository level, or `.git` (a directory or a worktree file). A nested
   `Package.swift` below a workspace or project does not become the root.
2. The layout lists its packages (every `Package.swift`), Xcode containers, and the repository root.
3. DerivedData is matched by `info.plist` `WorkspacePath` equal to one of the layout's containers, newest first; a
   `-derivedDataPath` root (no `<Project>-<hash>` level) is accepted wherever DerivedData is.
4. `--index-store-build` builds with `swift build` for a package and with `xcodebuild build` (scheme from the option, or
   the only shared scheme) for an Xcode container, into the tool's cache directory.
5. Test, generated and script code is classified from the project (target kinds of `Package.swift`, product types of the
   project) before path conventions.

## Consequences

- One fixture set (a package, a project, a workspace, nested packages, two worktrees, a `-derivedDataPath` build) tests
  every tool.
- maintastic's DangerPlugins can pass its DerivedData root instead of searching for `Index.noindex/DataStore` itself.

## Open questions

- Reading `pbxproj` product types without a third-party parser: how much of the format is needed (to be probed on maintastic).
- `xcodebuild` auto-build duration and whether it should be allowed on CI at all (opt-in, as today).
