import Foundation
import ProjectModel
import SourceCorpus
import Testing

@Suite struct ExternalLocalDependenciesTests {
    @Test func `externalLocalDependencies parses AST local paths outside root and ignores comments`() throws {
        let base = NSTemporaryDirectory() + "ak-extdep-\(UUID().uuidString)"
        let pkg = base + "/app"
        let sibling = base + "/shared"
        try FileManager.default.createDirectory(atPath: pkg, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: sibling, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: base) }
        let manifest = """
            // swift-tools-version: 6.4
            import PackageDescription
            let package = Package(
                name: "App",
                dependencies: [
                    // .package(path: "../commented-out"),
                    .package(path: "../shared"),
                    .package(path: "LocalInside"),
                ]
            )
            """
        try manifest.write(toFile: pkg + "/Package.swift", atomically: true, encoding: .utf8)
        let outside = ProjectLayout.externalLocalDependencies(root: pkg, packageDirectory: pkg)
        #expect(outside == [SourcePath.canonical(sibling)])
    }
}
