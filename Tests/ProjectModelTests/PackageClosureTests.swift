import Foundation
import Testing

@testable import ProjectModel

/// The packages whose files can change what a file's package builds and tests (ADR-0031): its own and its local
/// path dependencies, transitively; nil when a manifest cannot be read without running it.
@Suite struct PackageClosureTests {
    private func manifest(_ name: String, dependencies: String) -> String {
        """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "\(name)",
            dependencies: \(dependencies),
            targets: [.target(name: "\(name)")]
        )
        """
    }

    @Test func `a package's closure follows local path dependencies transitively, not remote ones`() throws {
        try ProjectFixture.with { f in
            try f.file(
                "App/Package.swift",
                manifest(
                    "App",
                    dependencies: """
                        [.package(path: "../Kit"), .package(url: "https://example.com/x.git", from: "1.0.0")]
                        """
                )
            )
            try f.file(
                "Kit/Package.swift",
                manifest("Kit", dependencies: #"[.package(name: "Base", path: "../Base")]"#)
            )
            try f.file("Base/Package.swift", manifest("Base", dependencies: "[]"))
            try f.file("Lone/Package.swift", manifest("Lone", dependencies: "[]"))
            let app = try f.file("App/Sources/App/A.swift")
            let base = try f.file("Base/Sources/Base/B.swift")
            let classification = try f.classification(of: [app, base])
            #expect(classification.packageClosure(containing: app) == [f.path("App"), f.path("Base"), f.path("Kit")])
            #expect(classification.packageClosure(containing: base) == [f.path("Base")])
            #expect(classification.packageClosure(containing: f.path("Elsewhere/C.swift")) == nil)
        }
    }

    @Test func `dependencies that are not literal, or changed after the call, make the closure unknown`() throws {
        try ProjectFixture.with { f in
            try f.file("App/Package.swift", manifest("App", dependencies: "deps"))
            try f.file(
                "Kit/Package.swift",
                manifest("Kit", dependencies: "[]") + "\npackage.dependencies.append(.package(path: \"../App\"))\n"
            )
            let app = try f.file("App/Sources/App/A.swift")
            let kit = try f.file("Kit/Sources/Kit/K.swift")
            let classification = try f.classification(of: [app, kit])
            #expect(classification.packageClosure(containing: app) == nil)
            #expect(classification.packageClosure(containing: kit) == nil)
        }
    }

    @Test func `a dependency outside the layout makes the closure unknown`() throws {
        try ProjectFixture.with { f in
            try f.file("App/Package.swift", manifest("App", dependencies: #"[.package(path: "../Missing")]"#))
            let app = try f.file("App/Sources/App/A.swift")
            #expect(try f.classification(of: [app]).packageClosure(containing: app) == nil)
        }
    }

    @Test func `local dependencies are read as spelled, without running the manifest`() {
        #expect(PackageManifestReader.localDependencies("let package = Package(name: \"P\")") == [])
        #expect(
            PackageManifestReader.localDependencies(
                #"let package = Package(name: "P", dependencies: [.package(path: "../A"), .package(path: "B")])"#
            ) == ["../A", "B"]
        )
        #expect(
            PackageManifestReader.localDependencies(
                #"let package = Package(name: "P", dependencies: [.package(path: name)])"#
            ) == nil
        )
        #expect(
            PackageManifestReader.localDependencies(#"let package = Package(name: "P", dependencies: list + [])"#)
                == nil
        )
    }
}
