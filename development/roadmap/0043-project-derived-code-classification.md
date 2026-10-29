---
status: done
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

## Done

Diary 2026-10-29-23; ADR-0024; research 2026-10-29-project-classification. analyzerkit `fa61e6b` red (18 tests, two
guards passing against the stub), `11cedb8` green.

- `ProjectClassification.load(layout)` reads every manifest and `.xcodeproj` of a `ProjectLayout`, running nothing;
  `classify(_:)` and `classify(_:tree:)` give a `FileClassification` (region and provenance: targets, manifest, run
  script, build output, or a convention with its reason); `issues(for:)` reports `project-unknown` and
  `project-unclaimed`; `conventionsOnly` for callers with no layout.
- Decision order: a manifest is a script; a Swift file a run-script phase runs is a script; then the targets compiling
  the file (the innermost package, and every Xcode project enclosing it). A file is test only when every one of its
  targets is a test target, so a source shared by the app and its UI tests is production. Run-script outputs are
  generated. With no target: path conventions, recorded as unknown, unclaimed or no project.
- Manifests are read as syntax (SwiftParser): a single `Package(…)` call with a literal `targets:` list of
  `.target`-style calls with literal names, paths, sources and excludes. Anything else (a variable, `map`, `#if`, a later
  `append`, `=` or `+=` on `targets`, `path`, `sources` or `exclude`, interpolation) makes the package unknown.
  SwiftPM's default directories (`Sources`, `Source`, `src`, `srcs`; `Tests` for test targets; `Plugins`) are honoured.
- `project.pbxproj` is read by an OpenStep parser of our own (bounded nesting): native targets and product types,
  explicit sources through their groups and the `<group>`, `SOURCE_ROOT` and `<absolute>` source trees, synchronized
  folders and their exception sets (which flip membership for their target), and run-script `outputPaths` and the
  Swift files a script names, with `SRCROOT`, `PROJECT_DIR` and `SOURCE_ROOT` expanded.
- maintastic (read-only, release): 2,980 files, 17 manifests and one project. Load 8 ms (Foundation's
  `PropertyListSerialization` alone took 556 ms on the project); classifying every file 59–63 ms, of which 27 ms is
  `GeneratedCode.isGenerated(path:)` and 9 ms `TestConventions.isTestPath` (their speed-up follows separately). 2,578
  production and 381 test files by target, one shared by the app and its UI tests, 17 manifests, one script
  (`scripts/clean_localizable_full.swift`, which the "Clean Localizable" phase also lists as an output), 0 unknown
  projects, 0 disagreements with path conventions; `Dangerfile.swift` and `Dangerfile.hooks.swift` are reported as
  unclaimed. No target compiles them.

Not covered: `.xcfilelist` inputs and outputs; aggregate and legacy targets; file references in other source trees
(`BUILT_PRODUCTS_DIR`, `SDKROOT`, custom) and paths that need another build setting; version-specific manifests
(`Package@swift-x.swift`) when choosing which to read; workspaces referencing projects outside the layout's root.
ProjectModel's Linux build is not compiled (only macOS). The cross-tool agreement moves to 0018–0022.
