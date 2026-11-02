import Foundation
import Testing

@testable import SourceCorpus

/// The bounded, link-refusing copy with its content identity (ADR-0030).
@Suite struct TreeSnapshotTests {
    private func tree(_ files: [String: String]) throws -> String {
        let root = FileManager.default.temporaryDirectory.appending(path: "snapshot-\(UUID().uuidString)").path
        for (path, text) in files {
            let full = root + "/" + path
            try FileManager.default.createDirectory(
                atPath: (full as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            try Data(text.utf8).write(to: URL(fileURLWithPath: full))
        }
        return root
    }

    @Test func `a copy holds every file, skips the build directories, and its manifest matches the source's`()
        async throws
    {
        let source = try tree([
            "Package.swift": "// manifest", "Sources/A/A.swift": "let a = 1", "Sources/A/Deep/B.swift": "let b = 2",
            ".build/x.o": "object", ".hidden": "kept",
        ])
        let destination = source + "-copy"
        defer {
            try? FileManager.default.removeItem(atPath: source)
            try? FileManager.default.removeItem(atPath: destination)
        }
        let (manifest, cloned) = try await TreeSnapshot.copy(from: source, to: destination)
        #expect(
            manifest.entries.map(\.path) == [".hidden", "Package.swift", "Sources/A/A.swift", "Sources/A/Deep/B.swift"]
        )
        #expect(manifest.directories == ["Sources", "Sources/A", "Sources/A/Deep"])
        #expect(!FileManager.default.fileExists(atPath: destination + "/.build"))
        #expect(try String(contentsOfFile: destination + "/Sources/A/Deep/B.swift", encoding: .utf8) == "let b = 2")
        #if os(macOS)
            #expect(cloned == 4)  // the temporary directory is on APFS
        #endif
        let copied = try await TreeSnapshot.inventory(destination)
        #expect(copied.digest == manifest.digest)
        #expect(try await TreeSnapshot.verify(destination, against: manifest).isEmpty)
        // A changed, an added and a removed file.
        try Data("let a = 3".utf8).write(to: URL(fileURLWithPath: destination + "/Sources/A/A.swift"))
        try Data("new".utf8).write(to: URL(fileURLWithPath: destination + "/New.swift"))
        try FileManager.default.removeItem(atPath: destination + "/.hidden")
        let differences = try await TreeSnapshot.verify(destination, against: manifest)
        #expect(Set(differences) == [.changed("Sources/A/A.swift"), .added("New.swift"), .removed(".hidden")])
        // The source is untouched by edits to the copy.
        #expect(try String(contentsOfFile: source + "/Sources/A/A.swift", encoding: .utf8) == "let a = 1")
    }

    @Test func `a link is refused and nothing is left behind`() async throws {
        let source = try tree(["A.swift": "let a = 1"])
        let destination = source + "-copy"
        defer {
            try? FileManager.default.removeItem(atPath: source)
            try? FileManager.default.removeItem(atPath: destination)
        }
        try FileManager.default.createSymbolicLink(atPath: source + "/Link.swift", withDestinationPath: "/etc/hosts")
        await #expect(throws: TreeSnapshot.Failure.self) { try await TreeSnapshot.copy(from: source, to: destination) }
        #expect(!FileManager.default.fileExists(atPath: destination))
    }

    @Test func `a destination inside the source or already there is refused`() async throws {
        let source = try tree(["A.swift": "let a = 1"])
        defer { try? FileManager.default.removeItem(atPath: source) }
        await #expect(throws: TreeSnapshot.Failure.self) {
            try await TreeSnapshot.copy(from: source, to: source + "/inner")
        }
        await #expect(throws: TreeSnapshot.Failure.self) { try await TreeSnapshot.copy(from: source, to: source) }
        var limits = TreeSnapshot.Limits()
        limits.maxFileBytes = 4
        let destination = source + "-copy"
        defer { try? FileManager.default.removeItem(atPath: destination) }
        await #expect(throws: TreeSnapshot.Failure.self) {
            try await TreeSnapshot.copy(from: source, to: destination, limits: limits)
        }
        #expect(!FileManager.default.fileExists(atPath: destination))
    }

    @Test func `the digest names the tree, not the order of reading`() {
        let one = TreeSnapshot.Manifest(
            entries: [.init(path: "b", size: 1, sha256: "2"), .init(path: "a", size: 1, sha256: "1")],
            directories: []
        )
        let two = TreeSnapshot.Manifest(
            entries: [.init(path: "a", size: 1, sha256: "1"), .init(path: "b", size: 1, sha256: "2")],
            directories: []
        )
        #expect(one.digest == two.digest)
        #expect(one.digest.count == 64)
        #expect(one.totalBytes == 2)
    }

    @Test func `under the skip policy a link is left out, listed, and never followed`() async throws {
        let source = try tree(["A.swift": "let a = 1"])
        let destination = source + "-copy"
        defer {
            try? FileManager.default.removeItem(atPath: source)
            try? FileManager.default.removeItem(atPath: destination)
        }
        try FileManager.default.createDirectory(atPath: source + "/.claude", withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: source + "/.claude/skills", withDestinationPath: "/etc")
        var limits = TreeSnapshot.Limits()
        limits.links = .skip
        let (manifest, _) = try await TreeSnapshot.copy(from: source, to: destination, limits: limits)
        #expect(manifest.skippedLinks == [".claude/skills"])
        #expect(manifest.entries.map(\.path) == ["A.swift"])
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: destination + "/.claude/skills")) == nil)
        #expect(!FileManager.default.fileExists(atPath: destination + "/.claude/skills"))
    }
}
