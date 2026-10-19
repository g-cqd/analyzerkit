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
        .library(name: "ProjectModel", targets: ["ProjectModel"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "604.0.0")
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
