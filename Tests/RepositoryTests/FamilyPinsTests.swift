import Foundation
import Testing

/// `Scripts/family-pins.sh` (roadmap 0049, ADR-0025): SwiftPM refuses two revision-based requirements on one package
/// written differently, even a revision and a branch naming the same commit; the script finds them in the manifests
/// before a resolution fails.
@Suite struct FamilyPinsTests {
    private static let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "Scripts/family-pins.sh").path

    private func family(_ manifests: [String: String], _ body: (String) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "family-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for (name, manifest) in manifests {
            let directory = root.appending(path: name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try manifest.write(to: directory.appending(path: "Package.swift"), atomically: true, encoding: .utf8)
        }
        try body(root.path)
    }

    private func run(_ root: String) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [Self.script, root]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private static func manifest(_ requirement: String, extra: String = "") -> String {
        """
        // swift-tools-version: 6.2
        import PackageDescription
        let package = Package(
            name: "P",
            dependencies: [
                .package(
                    url: "https://github.com/swiftlang/indexstore-db.git",
                    \(requirement)),
                .package(path: "../Local"),\(extra)
            ])
        """
    }

    @Test func `a branch beside two revisions fails and names the package`() throws {
        try family([
            "Kit": Self.manifest(#"revision: "0390867818c28241af4650eb4ef29af5669335a3""#),
            "Tool": Self.manifest(#"revision: "0390867818c28241af4650eb4ef29af5669335a3""#),
            "Search": Self.manifest(#"branch: "release/6.4.x""#),
        ]) { root in
            let (status, output) = try run(root)
            #expect(status == 1, "\(output)")
            #expect(output.contains("indexstore-db"))
            #expect(output.contains("Search"))
            #expect(output.contains(#"branch: "release/6.4.x""#))
        }
    }

    @Test func `identical revisions pass, and version ranges may differ`() throws {
        let parser = #".package(url: "https://github.com/apple/swift-argument-parser", from: "1.%@"),"#
        try family([
            "Kit": Self.manifest(
                #"revision: "0390867818c28241af4650eb4ef29af5669335a3""#,
                extra: "\n        " + parser.replacingOccurrences(of: "%@", with: "5.1")),
            "Tool": Self.manifest(
                #"revision: "0390867818c28241af4650eb4ef29af5669335a3""#,
                extra: "\n        " + parser.replacingOccurrences(of: "%@", with: "8.1")),
        ]) { root in
            let (status, output) = try run(root)
            #expect(status == 0, "\(output)")
            #expect(output.contains("indexstore-db"))
        }
    }

    @Test func `a revision against a version range fails`() throws {
        try family([
            "Kit": Self.manifest(#"revision: "0390867818c28241af4650eb4ef29af5669335a3""#),
            "Tool": Self.manifest(#"from: "1.0.0""#),
        ]) { root in
            let (status, output) = try run(root)
            #expect(status == 1, "\(output)")
        }
    }
}
