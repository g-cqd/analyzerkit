# analyzerkit

The common ground of a family of Swift static analyzers:
[arcleak](https://github.com/g-cqd/arcleak) (retain cycles and leaks), [deadwood](https://github.com/g-cqd/deadwood) (unused and
dead code), [dolly](https://github.com/g-cqd/dolly) (duplicated code), [fcheck](https://github.com/g-cqd/fcheck) (obligations on
every path out of a function) and [modeler](https://github.com/g-cqd/modeler) (diagrams and model checking), plus
[swift-search](https://github.com/g-cqd/swift-search).

They all need the same answers before they look at a rule: which code the system, a test framework or a script runner starts
without any call site; which code only debug builds, previews or generators produce; how to read a corpus quickly, keep what was
extracted from it, and report findings the same way everywhere. analyzerkit holds those answers, so what one tool learns reaches
the others.

## For people using the analyzers

The tools behave alike on purpose. [How the analyzers behave](docs/analyzer-contract.md) describes what they share: the
configuration file, scoping a report to a pull request, baselines, exit codes, the JSON and SARIF reports, and the cache.

## For people writing a tool

analyzerkit is a set of independent SwiftPM libraries. [Libraries](docs/libraries.md) lists each one and what it answers.

| Library | For |
| --- | --- |
| `ProjectModel` | the model of a project: layout, code regions, entry points the system starts, generated and test code |
| `SourceCorpus`, `CorpusScan` | finding, reading and fingerprinting files, and a parallel scan with a facts cache |
| `AnalyzerCLI`, `AnalyzerConfiguration` | the shared options, exit statuses, and the configuration file |
| `ReportSupport`, `Suppression` | the xcode, JSON and SARIF reports, baselines, and comment directives |
| `IndexStoreSupport` | finding and trusting the compiler's index store |
| `ControlFlow`, `SymbolFacts` | a control-flow graph with dataflow, and what a file declares and references |
| `SemanticEmbedding`, `WordPiece` | embedding providers and a WordPiece tokenizer for the opt-in semantic features |

```swift
.package(url: "https://github.com/g-cqd/analyzerkit.git", from: "0.4.0")
```

```swift
.product(name: "ProjectModel", package: "analyzerkit")
```

The libraries follow semantic versioning. While the major version is 0, a minor release may change the API, so the analyzers pin
an exact revision for reproducible builds.

## Requirements

Swift 6.4. macOS 15 or later, or Linux; the index store, Core ML and NaturalLanguage features are macOS-only.

## Development

```sh
swift build --build-tests
swift test --skip-build
```

How the repository is run (decisions, plans, the working log) is in [`development/`](development/).

[MIT](LICENSE)
