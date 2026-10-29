---
status: not-started
blocked-by: []
date: 2026-10-29
---

# 0043 — Project-derived test, generated and script classification

Split from roadmap 0008 (diary 2026-10-29-11); fulfills ADR-0003 item 5. ProjectLayout now supplies filesystem layout,
not target semantics. Keep the semantic work explicit rather than treating filename discovery as classification.

Probe first: parse SwiftPM target kinds without executing Package.swift; determine the minimum pbxproj grammar needed
for product types, target memberships, generated sources and scripts, including synchronized folders. Record ambiguous
or dynamic cases as unknown; do not silently classify them as production. Evaluate SwiftSyntax and existing parsers
before adding another dependency or building a parser.

Scope: a shared ProjectModel classification using target kinds and Xcode product types before path conventions, with
provenance and conservative fallback for dynamic manifests, missing projects, conflicting memberships and unsupported
constructs. No execution of project scripts or manifests during ordinary analysis.

Red: package test targets with unconventional paths, non-test code under Tests, Xcode test/application/library products,
a source shared by test and production targets, generated-source build phases, nested local packages and unknown syntax.
All tools must agree on region selection for the same fixture and configuration.

Acceptance: fixtures green in ProjectModel and the five tool migrations; measured on maintastic read-only; duplicated
project/path classifiers removed where superseded, unknown cases surfaced. Xcode index builds are separately 0033.
