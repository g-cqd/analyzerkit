# analyzerkit

Shared infrastructure for the Swift static analysis and testing tools: [arcleak](https://github.com/g-cqd/arcleak), [deadwood](https://github.com/g-cqd/deadwood), [dolly](https://github.com/g-cqd/dolly), [fcheck](https://github.com/g-cqd/fcheck), [modeler](https://github.com/g-cqd/modeler), [litmus](https://github.com/g-cqd/litmus), and [swift-search](https://github.com/g-cqd/swift-search).

Provides consistent SwiftPM/Xcode project discovery, symlink-safe corpus snapshots, incremental LMDB fact caching, shared CLI/configuration handling, suppression comments, IndexStore/toolchain verification, control-flow graphs, and SARIF/Xcode/JSON reporting.

## Requirements

- Swift 6.4+ (Swift 6 language mode, strict memory safety)
- macOS 15+ or Linux (`IndexStoreSupport` and CoreML embedding features are macOS-only)

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/g-cqd/analyzerkit.git", branch: "main")
]
```

## Products

| Product | Description |
| --- | --- |
| `SourceCorpus` | Canonical path resolution, bounded file reads, symlink-safe `TreeSnapshot`, large-stack parser runner |
| `ProjectModel` | SwiftPM/Xcode/workspace discovery, entry points, test targets, diff/change scoping |
| `CorpusScan` | Incremental parallel corpus scanning and LMDB-backed `FactsStore` |
| `SymbolFacts` | Shared syntactic symbol extraction |
| `ControlFlow` | Intra-procedural control-flow graph construction |
| `AnalyzerConfiguration` | Shared `.swift-analyzers.json` and per-tool configuration resolution |
| `AnalyzerCLI` | Shared command-line flags, exit codes, and diagnostics presentation |
| `Suppression` | Inline suppression and baseline matching |
| `ReportSupport` | Text, Xcode, JSON, and SARIF 2.1.0 report formatting |
| `IndexStoreSupport` | `BinaryTrustChecker`, `ToolchainResolution`, `BoundedProcess`, and IndexStoreDB sessions |
| `WordPiece` / `SemanticEmbedding` | Tokenization and local embedding bundle discovery |

## Documentation

- [Analyzer Contract](docs/analyzer-contract.md)
- [Libraries](docs/libraries.md)
- [Architecture Decisions](docs/adr/)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)

## License

[MIT](LICENSE)
