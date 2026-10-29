# analyzerkit

The model of a Swift project that static analyzers share: which code the
system, the test frameworks or a script runner starts without any Swift call
site, and which code only debug builds, previews or generators produce.

deadwood (unused code), arcleak (retain cycles and leaks) and dolly (code
clones) each need the same answers. Kept here, a rule learned by one tool
reaches the others.

## Library: `ProjectModel`

| API | Answers |
| --- | --- |
| `ProjectLayout` | the root, local packages and Xcode containers shared by the input paths; DerivedData matched by canonical `WorkspacePath`, not worktree folder names |
| `CodeRegion` | the kind of code: production, `debugOnly`, `preview`, `test`, `mock`, `generated`, `script` (an option set; a preview in `#if DEBUG` is both) |
| `CodeRegionScanner` | the line spans of a file that only debug builds (`#if DEBUG`) or previews (`#Preview`, `PreviewProvider`) compile |
| `TopLevelCodeScanner` | code at file scope that no declaration names: `#Preview` bodies, other freestanding macros, script statements |
| `ConditionalCompilation` | whether an `#if` clause compiles only in debug builds |
| `SystemEntryPoints` | the classes project files tell the system to create: Info.plist principal, extension and scene-delegate classes, their `INFOPLIST_KEY_` build settings, storyboard and xib `customClass` |
| `GeneratedCode` | whether a generator wrote a file, from its header or its path |
| `TestConventions` | the attributes and base class the test frameworks look for, and whether a file is test code (its imports or its path) |
| `ProjectPlatforms` | the platforms a project builds for, from an Xcode project's `SDKROOT` or a manifest's `platforms`, as `#if os(...)` names |
| `ReportScope`, `ScopedFinding` | narrows a report to a set of files; a finding is kept when any of its locations is in scope |
| `ReportSchema` | the version of the JSON report contract shared by the analyzers |

Scanners are syntactic or textual: no build and no index query. `ProjectLayout` also performs filesystem and plist
reads through Foundation and SourceCorpus; it never executes manifests or project scripts. Each scanner states its
complexity; all are linear in their input.

## Library: `AnalyzerCLI`

| API | Answers |
| --- | --- |
| `ExitStatus`, `RunOutcome` | the six exit statuses of every analyzer and when a run fails (ADR-0018): an error, a warning under `--strict`, never a note; 70 when every file found was skipped |
| `InputOptions`, `OutputOptions`, `RuleOptions`, `CacheOptions`, `IndexOptions`, `ExperimentalOptions` | the shared ArgumentParser option groups (ADR-0019), deprecated spellings folded in and reported as `Deprecation`s |

## Library: `AnalyzerConfiguration`

| API | Answers |
| --- | --- |
| `SharedConfiguration.resolve` | the configuration of one run (ADR-0021): one directory found by `stat` alone, `.swift-analyzers.json`'s top level and the tool's section, then the tool's own file, merged (`exclude` lists add up, objects merge key by key), every key checked, a key given twice refused; the merged JSON for the tool's own decoder |
| `Resolved.verboseLines` | what `--verbose` prints: the files read and which source won each key set more than once |

A sample shared file every tool reads: [`docs/.swift-analyzers.json`](docs/.swift-analyzers.json).

## Library: `IndexStoreSupport`

| API | Answers |
| --- | --- |
| `ToolchainResolution.resolve` | the first trusted `libIndexStore.dylib` from `DEVELOPER_DIR`, `xcode-select`, `xcrun`, user toolchains, then CLT; canonical path and rejection diagnostics |
| `BinaryTrustChecker.assess` | whether the resolved regular file belongs to root/current user and neither it nor its immediate parent is group/world-writable; a reason when rejected |

Shared by arcleak and deadwood. Discovery does not execute project code or load a library; selection is not proof of
index coverage. System probes are macOS-only; the policy has injected-command fixture tests. This is the first part of
the product: store normalization, cache-owned databases, reader coverage and the bounded executor are roadmap 0010.
The current narrow synchronous system probes have no deadline. Permission checks are defense in depth, not a sandbox
or a race-free guarantee against replacement before dlopen.

## Library: `SourceCorpus`

What every analyzer does before it looks at a rule, kept here so a fix reaches arcleak, dolly, deadwood and modeler
together. Each of these existed as a copy in each tool; the copies had drifted (only deadwood and dolly kept a link out of
the walked directory out of the corpus).

| API | Answers |
| --- | --- |
| `SourcePath` | one spelling per file: absolute, lexically standardized, symlinks resolved; repeats dropped |
| `SourceDiscovery` | the files under a directory that a predicate accepts, each directory walked once, links out of the root not followed |
| `PathFilter` | shared substring/glob exclusion rules, anchored at the configuration root, usable for directory pruning |
| `RepositoryRoot` | the repository a path lives in, so fingerprints do not depend on the checkout's location |
| `BoundedFileReader` | a regular file's bytes with a size cap, from one `open`, `fstat` and `pread` |
| `ContentFingerprint` | the XXH64 identity of a file's bytes and a salt, for cache entries |
| `BuildIdentity` | which build of a tool is running, so one build's cached facts are not read by another |
| `BoundedFileReader.readConfiguration` | a configuration or baseline file's bytes, stat first, with the wording of Foundation's errors that the analyzers print |

## Library: `CorpusScan`

| API | Answers |
| --- | --- |
| `FactsCache<Facts>` | per-file facts keyed by path and fingerprint, written with AemiJSON, failing open on a missing, foreign or corrupt file |
| `CorpusScanner.scan` | canonicalize, read, fingerprint, reuse or extract in parallel (bounded by Aemi's `mapConcurrently`), prune, persist |

`SourceCorpus` depends on Aemi's `AemiKernel` and `AemiIO`; `CorpusScan` adds `AemiRuntime` and AemiJSON.

## Library: `ReportSupport`

| API | Answers |
| --- | --- |
| `ArtifactURI` | how a SARIF log names a file: relative to the base when it is made of unescaped characters, else an absolute percent-encoded `file://` URI |
| `SarifColumns` | a UTF-8 byte column as the UTF-16 code-unit column SARIF declares, with the byte-order mark handled as the analyzer's parse did |
| `ReportEnvelope`, `RunNote`, `SkippedFile` | the JSON keys every report carries (ADR-0017): `schemaVersion`, `tool`, `version`, `runNotes`, `skippedFiles`, `timings`, added after the tool's own keys |
| `ReportSummary.notChecked` | the "(N not checked)" phrase of the one-line summary |
| `Sarif` | one SARIF 2.1.0 model for the analyzers; optional members omitted when nil, so each tool keeps its bytes |
| `PathPresenter` | `--relative-to`: a path inside the root loses its prefix, one outside stays absolute, free text loses the prefix |
| `BaselineFile` | the baseline file: sorted unique fingerprints, the tool, `version` 1 or none; validated on load |
| `XcodeDiagnostic` | one `path:line:column: severity: [rule] message` line |

`ProjectModel` also holds `Severity` and `Array.partitioned(by:)`, which every analyzer's report used a copy of.

## Library: `WordPiece`

A BERT WordPiece tokenizer over a model bundle's `vocab.txt`, so no analyzer links swift-transformers to feed a Core ML
bundle. Pure Swift; the analyzers' parity tests compare it with swift-transformers.

## Library: `ControlFlow`

| API | Answers |
| --- | --- |
| `ControlFlowGraph.build` | the control flow of a function body: a node per statement and condition, an edge for each way control goes on, including a `try` that throws and the `defer`s a `return`, `throw`, `break` or `continue` runs |
| `ControlFlowGraph.solve` | a forward dataflow over it, with a transfer per edge, so a condition can say something different on its true and false edges |
| `path`, `reachable` | a shortest path between two nodes, for the witness of a finding; the nodes control can reach |

Closures and nested functions are steps of the function that contains them, not entered.

## Use

```swift
.package(url: "https://github.com/g-cqd/analyzerkit.git", from: "0.1.0")
```

```swift
.product(name: "ProjectModel", package: "analyzerkit")
```

Releases are tagged starting at 0.1.0 and follow semantic versioning; while the
major version is 0, a minor release may change the API. The analyzers may pin an
exact revision instead, for reproducible builds.

## Report scope

`ReportScope` is the `--only` file list every analyzer shares. The whole corpus
is analyzed; only the report is scoped. A finding is kept when any of its
locations (primary or related) is in scope. The scope holds canonical paths: the
caller injects the canonicalizer that spells entries the way its findings' paths
are spelled, because the library cannot canonicalize without Foundation. A
path-printing option therefore changes what is printed, never what is kept. The
library does not resolve paths itself: the canonicalizer a tool injects decides how
a `--only` entry resolves (arcleak resolves a relative entry against the working
directory), so finding paths and `--only` entries must be canonicalized the same
way. An empty scope keeps nothing, so the report is empty; the tools exit 0 on an empty
report. "No scope" is a `nil` `ReportScope?`, never an empty one.

## Report schema

`ReportSchema.version` is the version of the JSON report contract shared by
arcleak, dolly and deadwood, written as the top-level `schemaVersion` field of
`--format json`. The compatibility rule is in the `ReportSchema` doc comment.

## Develop

```sh
swift build --build-tests
swift test --skip-build
```

Swift 6.4 (`.swift-version`), formatted with `swift format` (`.swift-format`).

## License

MIT, see `LICENSE`.
