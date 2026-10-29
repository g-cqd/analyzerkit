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
        .library(name: "ProjectModel", targets: ["ProjectModel"]),
        .library(name: "SourceCorpus", targets: ["SourceCorpus"]),
        .library(name: "CorpusScan", targets: ["CorpusScan"]),
        .library(name: "ReportSupport", targets: ["ReportSupport"]),
        .library(name: "WordPiece", targets: ["WordPiece"]),
        .library(name: "ControlFlow", targets: ["ControlFlow"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "604.0.0"),
        // The byte kernels, POSIX file and bounded-concurrency primitives `SourceCorpus` is built on.
        .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "f6da05cd0efdf60700e854efb5b6092eae89b8c5"),
        // The JSON coder behind the per-file facts cache.
        .package(url: "https://github.com/g-cqd/AemiJSON.git", revision: "5542d37ff0edb17c822b48fe69bff6e792354c57"),
    ],
    targets: [
        // The shared model of a Swift project: entry points the system or the
        // test frameworks create, code regions, generated files, and the shared
        // report contract (scope, schema version).
        .target(
            name: "ProjectModel",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax")
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
            ],
            swiftSettings: strictSwiftSettings
        ),
        // The per-file facts cache and the parallel scan that uses it.
        .target(
            name: "CorpusScan",
            dependencies: [
                "SourceCorpus",
                .product(name: "AemiRuntime", package: "aemi"),
                .product(name: "AemiJSON", package: "AemiJSON"),
            ],
            swiftSettings: strictSwiftSettings
        ),
        // What the SARIF and xcode reports of every analyzer say about a location.
        .target(
            name: "ReportSupport",
            dependencies: ["SourceCorpus"],
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
            dependencies: ["CorpusScan", "SourceCorpus"],
            swiftSettings: strictSwiftSettings
        ),
        // The repository's own rules: the documentation law of `development/WHITE-PAPER.md` (roadmap 0001).
        .testTarget(name: "RepositoryTests", swiftSettings: strictSwiftSettings),
        .testTarget(
            name: "ProjectModelTests",
            dependencies: [
                "ProjectModel",
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            swiftSettings: strictSwiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
