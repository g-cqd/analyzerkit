# Libraries

Each product of analyzerkit, and what it answers. They are independent: depend on the ones you need.

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
| `ExitStatus`, `RunOutcome` | the six exit statuses of every analyzer and when a run fails: an error, a warning under `--strict`, never a note; 70 when every file found was skipped |
| `InputOptions`, `OutputOptions`, `RuleOptions`, `CacheOptions`, `IndexOptions`, `ExperimentalOptions` | the shared ArgumentParser option groups, deprecated spellings folded in and reported as `Deprecation`s |

## Library: `AnalyzerConfiguration`

| API | Answers |
| --- | --- |
| `SharedConfiguration.resolve` | the configuration of one run: one directory found by `stat` alone, `.swift-analyzers.json`'s top level and the tool's section, then the tool's own file, merged (`exclude` lists add up, objects merge key by key), every key checked, a key given twice refused; the merged JSON for the tool's own decoder |
| `Resolved.verboseLines` | what `--verbose` prints: the files read and which source won each key set more than once |

A sample shared file every tool reads: [`.swift-analyzers.json`](.swift-analyzers.json).

## Library: `IndexStoreSupport`

| API | Answers |
| --- | --- |
| `ToolchainResolution.resolve` | the first trusted `libIndexStore.dylib` from `DEVELOPER_DIR`, `xcode-select`, `xcrun`, user toolchains, then CLT; canonical path and rejection diagnostics |
| `BinaryTrustChecker.assess` | whether the resolved regular file belongs to root/current user and neither it nor its immediate parent is group/world-writable; a reason when rejected |

Discovery does not execute project code or load a library, and selecting a library is not proof that the index covers the
code. The probes run only on macOS and have no deadline. Permission checks are defense in depth, not a sandbox or a guarantee
against replacement before the library is loaded.

## Library: `SourceCorpus`

What every analyzer does before it looks at a rule: find the files, read them within a size cap, and give each one a single
spelling and an identity.

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

`SourceCorpus` builds on Aemi's `AemiKernel` and `AemiIO`; `CorpusScan` adds `AemiRuntime` and AemiJSON.

## Library: `ReportSupport`

| API | Answers |
| --- | --- |
| `ArtifactURI` | how a SARIF log names a file: relative to the base when it is made of unescaped characters, else an absolute percent-encoded `file://` URI |
| `SarifColumns` | a UTF-8 byte column as the UTF-16 code-unit column SARIF declares, with the byte-order mark handled as the analyzer's parse did |
| `ReportEnvelope`, `RunNote`, `SkippedFile` | the JSON keys every report carries: `schemaVersion`, `tool`, `version`, `runNotes`, `skippedFiles`, `timings`, added after the tool's own keys |
| `ReportSummary.notChecked` | the "(N not checked)" phrase of the one-line summary |
| `Sarif` | one SARIF 2.1.0 model for the analyzers; optional members omitted when nil, so each tool keeps its bytes |
| `PathPresenter` | `--relative-to`: a path inside the root loses its prefix, one outside stays absolute, free text loses the prefix |
| `BaselineFile` | the baseline file: sorted unique fingerprints, the tool, `version` 1 or none; validated on load |
| `XcodeDiagnostic` | one `path:line:column: severity: [rule] message` line |
| `ToolReport`, `ToolReportFormat` | the xcode, JSON and SARIF renderers and the one-line summary: a tool says what its findings and report hold, and the wording, the order of the notes and the keys are fixed here |
| `FindingBaseline`, `Fingerprint` | the fingerprint of a finding (FNV-1a over rule, path, line, column and message) and the baseline file built on it |

`ProjectModel` also holds `Severity` and `Array.partitioned(by:)`, which every analyzer's report used a copy of.

## Library: `WordPiece`

A BERT WordPiece tokenizer over a model bundle's `vocab.txt`, so no analyzer links swift-transformers to feed a Core ML
bundle. Pure Swift; the analyzers' parity tests compare it with swift-transformers.

## Library: `Suppression`

| API | Answers |
| --- | --- |
| `DirectiveGrammar` | the comment directives (`// @dw:accept -- reason`, `accept:this`, `accept:next`, `disable`, `enable`) of a file, for a tool's namespaces |
| `Directive`, `DirectiveKind` | one parsed directive, with a coding that caches and reports share |
| `SuppressionTable` | which finding a directive silences: the line and the next, a disabled range, optionally scoped to rule ids |

## Library: `SemanticEmbedding`

| API | Answers |
| --- | --- |
| `SemanticEmbeddingProvider` | the contract of a model that turns a snippet into a vector |
| `NLContextualSemanticEmbeddingProvider` | Apple's on-device `NLContextualEmbedding` (macOS) |
| `HFSemanticEmbeddingProvider` | a Core ML sentence-embedding bundle with its WordPiece vocabulary (macOS) |
| `DeterministicEmbeddingProvider` | a character n-gram fallback that needs nothing, and gives the same vectors everywhere |
| `EmbeddingBundleLocator` | where a bundle is looked for: a flag, an environment variable, then next to the executable |
| `SemanticEmbeddingProviders.onDeviceOrFallback()` | the first provider that is available |

Platform code stays behind `#if canImport(CoreML)` and `#if canImport(NaturalLanguage)`; elsewhere only the deterministic provider
exists.

## Library: `ControlFlow`

| API | Answers |
| --- | --- |
| `ControlFlowGraph.build` | the control flow of a function body: a node per statement and condition, an edge for each way control goes on, including a `try` that throws and the `defer`s a `return`, `throw`, `break` or `continue` runs |
| `ControlFlowGraph.solve` | a forward dataflow over it, with a transfer per edge, so a condition can say something different on its true and false edges |
| `path`, `reachable` | a shortest path between two nodes, for the witness of a finding; the nodes control can reach |

Closures and nested functions are steps of the function that contains them, not entered.

## Library: `SymbolFacts`

| API | Answers |
| --- | --- |
| `FileSymbolFacts.collect` | what one file declares (locals and parameters too, macros included) and references, with the context of each reference, and the lexical scopes between; the string-literal and comment tokens a dynamic reference may hide in |
| `Declaration.nameLocation`, `Reference.nameLocation` | where the name is when the node starts elsewhere: after a declaration's attributes, the last component of `Outer.Inner` |
| `FileSymbolFacts` as AemiProtobuf, `SymbolFactsWire` | the facts as a cache payload, and each message for a payload that embeds them |

Fold the tree's operators first for an assignment to read as a write.

## Notes on `ReportScope` and `ReportSchema`

`ReportScope` holds canonical paths. The caller injects the canonicalizer that spells entries the way its findings' paths are
spelled, because the library cannot canonicalize without Foundation; a path-printing option therefore changes what is printed,
never what is kept. An empty scope keeps nothing, and "no scope" is a `nil` `ReportScope?`, never an empty one.

`ReportSchema.version` is the version of the JSON report contract, written as the top-level `schemaVersion` of `--format json`.
The compatibility rule is in its doc comment and in [How the analyzers behave](analyzer-contract.md#the-json-report).
