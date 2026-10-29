---
status: accepted
date: 2026-10-29
---

# 0024 — Code is classified from the project before its paths

## Context

ADR-0003 item 5 asks for test, generated and script code to be classified from the project before path conventions.
Today every tool calls `TestConventions` (a `Tests` component, a `…Tests.swift` name, an `XCTest` or `Testing` import) and
`GeneratedCode` (a header marker, a `Generated` component); deadwood adds its own glob. A test target at `Checks/`, a tool
target under `Tests/`, an Xcode UI-test folder named `Screenshots`, or a file both the app and its tests compile are all
misread. The probe (research 2026-10-29-project-classification) found maintastic's project built entirely from Xcode 16
synchronized folders, with membership exceptions that add files to a target as well as remove them, and its 17
manifests all literal.

## Decision

1. `ProjectClassification`, built once from a `ProjectLayout`, reads every `Package.swift` with SwiftSyntax and every
   `project.pbxproj` with a reader of the OpenStep property-list grammar in ProjectModel. Nothing is executed or built.
   (`PropertyListSerialization` took 556 ms on maintastic's 3,506-line project and is not part of FoundationEssentials.)
2. A package's targets come from the `targets:` array of its `Package(…)` call: kind, name, `path:` or SwiftPM's default
   directories, `sources:` and `exclude:`. A target owns its directory; a nested package owns its own tree. A manifest
   whose targets are not literal calls (a variable, a `map`, an `#if`, a non-literal path, `package.targets` changed
   after the call) is **unknown**.
3. An Xcode target's sources come from its sources phase (file references resolved through their groups and source
   trees) and from its synchronized folders, where a membership exception flips membership for its target: it removes a
   file from a target owning the folder and adds it to one that does not. Unit-test and UI-test product types are test;
   every other product type is production. A project that does not parse is **unknown**.
4. A file's region from the project: **test** when every target compiling it is a test target, production when any
   production target compiles it (it ships); **generated** when a run-script phase lists it as an output or its reference
   lives in a build-products or derived-files tree; **script** for a package manifest and a Swift file a run-script phase
   runs. Content signals stay on top of that: an `XCTest` or `Testing` import makes a file test, a generator's header
   makes it generated. The test path conventions apply only to a file no known project claims, and such a file is
   reported. Generated's name conventions (a `Generated` directory, `.generated.swift`) stay for every file: a project
   says which target compiles a file, not whether a committed file came from a generator.
5. Every classification carries its provenance (the targets, the phase, or "convention"), and unknown projects and
   unclaimed files are reported to the run (`project-unknown`, `project-unclaimed`), never silently counted as
   production.

## Consequences

- One classification for all five tools; deadwood's glob classifier and the tools' own calls to `TestConventions` go in
  their migrations (0018–0022).
- A fixture set (unconventional test paths, a tool target under `Tests`, Xcode products, a shared source, a generator
  phase, a nested package, a dynamic manifest) tests every tool against the same answers.
- `outputFileListPaths` (`.xcfilelist`) and workspaces that reference projects outside the layout's root are not read;
  a phase that uses only file lists produces no generated classification.
