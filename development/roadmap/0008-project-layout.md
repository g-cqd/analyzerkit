---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0008 — `ProjectLayout`: SwiftPM, Xcode, workspaces, nested packages, worktrees

Scope (ADR-0003): root from the analyzed paths; containers and packages listed; DerivedData matched by `WorkspacePath`
(newest first) and `-derivedDataPath` roots accepted; test, generated and script classification from target and product
kinds before path conventions.

Red: fixtures — a package; an Xcode project with nested local packages (maintastic's shape); a workspace; two worktrees
of one project with two DerivedData folders; a `-derivedDataPath` build. Today's tools pick the nested package as root and
miss the worktree's DerivedData (A5, D6).

Acceptance: every fixture resolves; on maintastic the worktree's own DerivedData is found from the repository root and from
`ShareAPI/Sources`.
