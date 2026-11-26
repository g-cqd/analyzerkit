// swift-tools-version: 6.4
import PackageDescription

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
        .library(name: "SemanticEmbedding", targets: ["SemanticEmbedding"]),
        .library(name: "ControlFlow", targets: ["ControlFlow"]),
        .library(name: "SymbolFacts", targets: ["SymbolFacts"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
        .package(url: "https://github.com/apple/swift-collections.git", exact: "1.7.6"),
        .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "9f8d1a3eafed0ad23919b9c68d33606632ce0659"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", exact: "1.0.2", traits: []),
        .package(url: "https://github.com/apple/swift-system.git", exact: "1.9.0"),
        .package(
            url: "https://github.com/swiftlang/indexstore-db.git",
            revision: "0390867818c28241af4650eb4ef29af5669335a3"
        ),
        .package(
            url: "https://github.com/g-cqd/AemiProtobuf.git",
            revision: "d8985c489aa19e285214d032ef98855b6b95f30b"
        ),
        .package(url: "https://github.com/g-cqd/AemiJSON.git", revision: "fb4478051725c95614e76b15ac11e9a5c6a502a3"),
    ],
    targets: [
        .target(
            name: "AnalyzerConfiguration",
            dependencies: [
                "SourceCorpus", .product(name: "AemiJSONCore", package: "AemiJSON"),
                .product(name: "OrderedCollections", package: "swift-collections"),
            ],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "AnalyzerConfigurationTests",
            dependencies: ["AnalyzerConfiguration"],
            swiftSettings: strictSwiftSettings
        ),
        .target(
            name: "AnalyzerCLI",
            dependencies: ["ProjectModel", .product(name: "ArgumentParser", package: "swift-argument-parser")],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "AnalyzerCLITests",
            dependencies: [
                "AnalyzerCLI", "ProjectModel", .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            exclude: ["Goldens"],
            swiftSettings: strictSwiftSettings
        ),
        .target(
            name: "Suppression",
            dependencies: [
                "CorpusScan", .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "AemiKernels", package: "aemi"),
                .product(name: "AemiProtobuf", package: "AemiProtobuf"),
                .product(name: "AemiProtobufCore", package: "AemiProtobuf"),
            ],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "SuppressionTests",
            dependencies: [
                "Suppression", "CorpusScan", .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "AemiProtobuf", package: "AemiProtobuf"),
                .product(name: "AemiProtobufCore", package: "AemiProtobuf"),
            ],
            swiftSettings: strictSwiftSettings
        ),
        .target(
            name: "IndexStoreSupport",
            dependencies: [
                "SourceCorpus", "ProjectModel", "ReportSupport", .product(name: "AemiKernel", package: "aemi"),
                .product(name: "AemiProcess", package: "aemi"),
                .product(name: "SwiftIfConfig", package: "swift-syntax"),
                .product(name: "IndexStoreDB", package: "indexstore-db", condition: .when(platforms: [.macOS])),
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "SystemPackage", package: "swift-system", condition: .when(platforms: [.linux])),
            ],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "IndexStoreSupportTests",
            dependencies: [
                "IndexStoreSupport", "ProjectModel", "ReportSupport",
                .product(name: "IndexStoreDB", package: "indexstore-db", condition: .when(platforms: [.macOS])),
                .product(name: "SwiftIfConfig", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "AemiProcess", package: "aemi"),
            ],
            swiftSettings: strictSwiftSettings
        ),
        .target(
            name: "ProjectModel",
            dependencies: [
                "SourceCorpus",
                .product(name: "AemiFileSystem", package: "aemi"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftIfConfig", package: "swift-syntax"),
            ],
            swiftSettings: strictSwiftSettings
        ),
        .target(
            name: "SourceCorpus",
            dependencies: [
                .product(name: "AemiKernel", package: "aemi"),
                .product(name: "AemiIO", package: "aemi"),
                .product(name: "AemiFileSystem", package: "aemi"),
                .product(name: "AemiRuntime", package: "aemi"),
                .product(name: "AemiDigest", package: "aemi"),
            ],
            swiftSettings: strictSwiftSettings
        ),
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
        .target(
            name: "ReportSupport",
            dependencies: ["SourceCorpus", "ProjectModel"],
            swiftSettings: strictSwiftSettings
        ),
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
        .target(
            name: "SymbolFacts",
            dependencies: [
                "CorpusScan", .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "AemiProtobuf", package: "AemiProtobuf"),
                .product(name: "AemiProtobufCore", package: "AemiProtobuf"),
            ],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "SymbolFactsTests",
            dependencies: [
                "SymbolFacts", .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "AemiProtobuf", package: "AemiProtobuf"),
            ],
            swiftSettings: strictSwiftSettings
        ),
        .target(name: "WordPiece", swiftSettings: strictSwiftSettings),
        .target(name: "SemanticEmbedding", dependencies: ["WordPiece"], swiftSettings: strictSwiftSettings),
        .testTarget(
            name: "SemanticEmbeddingTests",
            dependencies: ["SemanticEmbedding"],
            swiftSettings: strictSwiftSettings
        ),
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
