// swift-tools-version: 6.4
import PackageDescription

// Strict-by-default, as in the analyzers that use this package: warnings are
// errors, upcoming features are on, and strict memory safety keeps the unsafe
// surface at zero. Swift 6 language mode includes complete strict concurrency.
let strictSwiftSettings: [SwiftSetting] = [
    .treatAllWarnings(as: .error),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .strictMemorySafety(),
]

let package = Package(
    name: "analyzerkit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AnalyzerCLI", targets: ["AnalyzerCLI"]),
        .library(name: "AnalyzerConfiguration", targets: ["AnalyzerConfiguration"]),
        .library(name: "Suppression", targets: ["Suppression"]),
        .library(name: "IndexStoreSupport", targets: ["IndexStoreSupport"]),
        .library(name: "ProjectModel", targets: ["ProjectModel"]),
        .library(name: "SourceCorpus", targets: ["SourceCorpus"]),
        .library(name: "CorpusScan", targets: ["CorpusScan"]),
        .library(name: "ReportSupport", targets: ["ReportSupport"]),
        .library(name: "WordPiece", targets: ["WordPiece"]),
        .library(name: "ControlFlow", targets: ["ControlFlow"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "604.0.0"),
        // The option groups every analyzer's command line shares (AnalyzerCLI); the tools already use it.
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
        // OrderedCollections for the shared configuration's merge; the range AemiJSON already resolves.
        .package(url: "https://github.com/apple/swift-collections.git", "1.7.1"..<"1.8.0"),
        // The byte kernels, POSIX file and bounded-concurrency primitives `SourceCorpus` is built on.
        .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "a20fb18feff6a9ff54ebee5bb70f4bee126c9e8e"),
        // The JSON coder behind the per-file facts cache.
        // Subprocess runs the toolchain probes and index builds (IndexStoreSupport's BoundedProcess): a child in a session of
        // its own, torn down with its descendants. Its Foundation trait is not needed. swift-system supplies `FilePath` off
        // Apple platforms, as Subprocess itself uses it.
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "1.0.2", traits: []),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.5.0"),
        // IndexStoreDB opens index stores for IndexStoreSupport, on macOS only. No semver tags: pinned to one revision, which
        // arcleak and deadwood must pin too (SwiftPM resolves one revision per package in a graph).
        .package(
            url: "https://github.com/swiftlang/indexstore-db.git", revision: "0390867818c28241af4650eb4ef29af5669335a3"),
        // The wire format of the facts cache's shards (ADR-0011), pinned like AemiJSON to one revision on the same aemi.
        .package(
            url: "https://github.com/g-cqd/AemiProtobuf.git", revision: "4947dd13e9f591d6ae7d90780fcd4a6990a62735"),
        .package(url: "https://github.com/g-cqd/AemiJSON.git", revision: "08695007cbd23d2b6dbb2181e6f9b3dcf1666f83"),
    ],
    targets: [
        // The configuration every analyzer reads: one directory, the shared `.swift-analyzers.json` and the tool's own
        // file, merged, every key checked (ADR-0020).
        .target(
            name: "AnalyzerConfiguration",
            dependencies: [
                "SourceCorpus", .product(name: "AemiJSONCore", package: "AemiJSON"),
                .product(name: "OrderedCollections", package: "swift-collections"),
            ],
            swiftSettings: strictSwiftSettings),
        .testTarget(
            name: "AnalyzerConfigurationTests", dependencies: ["AnalyzerConfiguration"],
            swiftSettings: strictSwiftSettings),
        // What every analyzer's command line shares: exit statuses and when a run fails (ADR-0018), then the option
        // groups of ADR-0006.
        .target(
            name: "AnalyzerCLI",
            dependencies: ["ProjectModel", .product(name: "ArgumentParser", package: "swift-argument-parser")],
            swiftSettings: strictSwiftSettings),
        .testTarget(
            name: "AnalyzerCLITests",
            dependencies: [
                "AnalyzerCLI", "ProjectModel", .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            exclude: ["Goldens"],
            swiftSettings: strictSwiftSettings),
        .target(
            name: "Suppression",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "AemiKernels", package: "aemi"),
            ], swiftSettings: strictSwiftSettings),
        .testTarget(
            name: "SuppressionTests",
            dependencies: [
                "Suppression", .product(name: "SwiftParser", package: "swift-syntax"),
            ], swiftSettings: strictSwiftSettings),
        .target(
            name: "IndexStoreSupport",
            dependencies: [
                "SourceCorpus", "ProjectModel", "ReportSupport", .product(name: "AemiKernel", package: "aemi"),
                .product(name: "IndexStoreDB", package: "indexstore-db", condition: .when(platforms: [.macOS])),
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "SystemPackage", package: "swift-system", condition: .when(platforms: [.linux])),
            ],
            swiftSettings: strictSwiftSettings),
        .testTarget(
            name: "IndexStoreSupportTests",
            dependencies: [
                "IndexStoreSupport", "ProjectModel", "ReportSupport",
                .product(name: "IndexStoreDB", package: "indexstore-db", condition: .when(platforms: [.macOS])),
            ],
            swiftSettings: strictSwiftSettings),
        // The shared model of a Swift project: entry points the system or the
        // test frameworks create, code regions, generated files, and the shared
        // report contract (scope, schema version).
        .target(
            name: "ProjectModel",
            dependencies: [
                "SourceCorpus",
                .product(name: "AemiFileSystem", package: "aemi"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                // Package manifests are read as syntax, never run (ADR-0024).
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            swiftSettings: strictSwiftSettings
        ),
        // What every analyzer does before it looks at a rule: find the Swift files, read and
        // fingerprint them, and tell one build of the tool from another.
        .target(
            name: "SourceCorpus",
            dependencies: [
                .product(name: "AemiKernel", package: "aemi"),
                .product(name: "AemiIO", package: "aemi"),
                .product(name: "AemiFileSystem", package: "aemi"),
            ],
            swiftSettings: strictSwiftSettings
        ),
        // The per-file facts cache and the parallel scan that uses it.
        .target(
            name: "CorpusScan",
            dependencies: [
                "SourceCorpus",
                .product(name: "AemiRuntime", package: "aemi"),
                .product(name: "AemiKernel", package: "aemi"),
                .product(name: "AemiIO", package: "aemi"),
                .product(name: "AemiJSON", package: "AemiJSON"),
                .product(name: "AemiProtobufCore", package: "AemiProtobuf"),
                .product(name: "AemiProtobuf", package: "AemiProtobuf"),
            ],
            swiftSettings: strictSwiftSettings
        ),
        // What the SARIF and xcode reports of every analyzer say about a location.
        .target(
            name: "ReportSupport",
            dependencies: ["SourceCorpus", "ProjectModel"],
            swiftSettings: strictSwiftSettings
        ),
        // The control flow of a function body, with its throwing and `defer` exits, for the analyzers that check a
        // property on every path.
        .target(
            name: "ControlFlow",
            dependencies: [.product(name: "SwiftSyntax", package: "swift-syntax")],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "ControlFlowTests",
            dependencies: ["ControlFlow", .product(name: "SwiftParser", package: "swift-syntax")],
            swiftSettings: strictSwiftSettings
        ),
        // A BERT WordPiece tokenizer, so no analyzer links swift-transformers to feed a Core ML bundle.
        .target(name: "WordPiece", swiftSettings: strictSwiftSettings),
        .testTarget(
            name: "ReportSupportTests",
            dependencies: ["ReportSupport", "ProjectModel"],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "SourceCorpusTests",
            dependencies: ["SourceCorpus"],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "CorpusScanTests",
            dependencies: [
                "CorpusScan", "SourceCorpus", .product(name: "AemiProtobuf", package: "AemiProtobuf"),
                .product(name: "AemiProtobufCore", package: "AemiProtobuf"),
            ],
            swiftSettings: strictSwiftSettings
        ),
        // The repository's own rules: the documentation law of `development/WHITE-PAPER.md` (roadmap 0001).
        .testTarget(name: "RepositoryTests", swiftSettings: strictSwiftSettings),
        .testTarget(
            name: "ProjectModelTests",
            dependencies: [
                "ProjectModel",
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftIfConfig", package: "swift-syntax"),
            ],
            swiftSettings: strictSwiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
