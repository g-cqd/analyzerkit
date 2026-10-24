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
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "604.0.0"),
        // The byte kernels, POSIX file and bounded-concurrency primitives `SourceCorpus` is built on.
        .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "afc1be3d578045b381e76f6b1712a81b39956ced"),
        // The JSON coder behind the per-file facts cache.
        .package(url: "https://github.com/g-cqd/AemiJSON.git", revision: "6bca1d8fade0236506726869fb626c4882fc2aea"),
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
        // fingerprint them, reuse cached facts, and extract the rest in parallel.
        .target(
            name: "SourceCorpus",
            dependencies: [
                .product(name: "AemiKernel", package: "aemi"),
                .product(name: "AemiIO", package: "aemi"),
                .product(name: "AemiRuntime", package: "aemi"),
                .product(name: "AemiJSON", package: "AemiJSON"),
            ],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "SourceCorpusTests",
            dependencies: ["SourceCorpus"],
            swiftSettings: strictSwiftSettings
        ),
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
