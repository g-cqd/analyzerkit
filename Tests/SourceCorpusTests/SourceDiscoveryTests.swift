import Foundation
import SourceCorpus
import Testing

/// The walk behind every analyzer's `analyze <directory>`. A symlinked subtree is analyzed like any other,
/// but no link may send the walk round a loop or out of the directory it was given: two links back to an
/// ancestor used to make it exponential, and a link out of the repository pulled another repository's files
/// into the corpus.
@Suite struct SourceDiscoveryTests {
    /// `root/A.swift` and `root/Sources/B.swift`, plus `outside/Shared.swift` beside the root.
    private func populate(_ scratch: Scratch) throws {
        try scratch.write("root/A.swift")
        try scratch.write("root/Sources/B.swift")
        try scratch.write("outside/Shared.swift")
    }

    private func realFiles(under root: String) -> [String] { [root + "/A.swift", root + "/Sources/B.swift"] }

    @Test func `a link back to an ancestor does not walk the tree again`() throws {
        try Scratch.with { scratch in
            try populate(scratch)
            try scratch.link("root/Sources/Loop", to: "..")
            let root = scratch.path("root")
            #expect(SourceDiscovery.swiftFiles(under: root) == realFiles(under: root))
        }
    }

    @Test func `two links back to an ancestor finish and list each file once`() throws {
        try Scratch.with { scratch in
            try populate(scratch)
            try scratch.link("root/Sources/Loop1", to: "..")
            try scratch.link("root/Sources/Loop2", to: "..")
            let root = scratch.path("root")
            #expect(SourceDiscovery.swiftFiles(under: root) == realFiles(under: root))
        }
    }

    @Test(arguments: [
        ("Shared", "../outside"), ("Linked.swift", "../outside/Shared.swift"), ("FileSystem", "/"),
    ])
    func `a link out of the root is not followed`(name: String, destination: String) throws {
        try Scratch.with { scratch in
            try populate(scratch)
            try scratch.link("root/" + name, to: destination)
            let root = scratch.path("root")
            #expect(SourceDiscovery.swiftFiles(under: root) == realFiles(under: root))
        }
    }

    /// The target is reached at its own path, so the spelling does not depend on which name sorts first.
    @Test func `a link inside the root lists its target once, at the target's own path`() throws {
        try Scratch.with { scratch in
            try populate(scratch)
            try scratch.link("root/Alias", to: "Sources")
            try scratch.link("root/Again.swift", to: "A.swift")
            let root = scratch.path("root")
            #expect(SourceDiscovery.swiftFiles(under: root) == realFiles(under: root))
        }
    }

    /// Exclusion follows the real location: excluding a directory excludes it under every alias, and a link named like an
    /// exclude pattern does not hide the directory it points to.
    @Test func `an excluded directory stays excluded under an alias, and an alias cannot hide its target`() throws {
        try Scratch.with { scratch in
            try populate(scratch)
            try scratch.link("root/Alias", to: "Sources")
            let root = scratch.path("root")
            #expect(SourceDiscovery.swiftFiles(under: root) { $0.hasSuffix("/Sources/") } == [root + "/A.swift"])
            #expect(SourceDiscovery.swiftFiles(under: root) { $0.hasSuffix("/Alias/") } == realFiles(under: root))
        }
    }

    @Test func `a root named through a link keeps its spelling and its containment`() throws {
        try Scratch.with { scratch in
            try populate(scratch)
            try scratch.link("root/Sources/Loop", to: "..")
            try scratch.link("Linked", to: "root")
            let linked = scratch.path("Linked")
            #expect(SourceDiscovery.swiftFiles(under: linked) == realFiles(under: linked))
        }
    }

    @Test(arguments: [false, true])
    func `a dangling link stays listed so the analyzer reports it degraded`(rootThroughLink: Bool) throws {
        try Scratch.with { scratch in
            try populate(scratch)
            try scratch.link("root/Sources/Broken.swift", to: "Missing.swift")
            try scratch.link("Linked", to: "root")
            let walked = rootThroughLink ? scratch.path("Linked") : scratch.path("root")
            #expect(
                SourceDiscovery.swiftFiles(under: walked) == realFiles(under: walked) + [
                    walked + "/Sources/Broken.swift"
                ]
            )
        }
    }

    @Test func `hidden entries and build products are skipped`() throws {
        try Scratch.with { scratch in
            try populate(scratch)
            for skipped in [".hidden", ".build", "DerivedData", ".swiftpm", "checkouts"] {
                try scratch.write("root/\(skipped)/X.swift")
            }
            try scratch.write("root/Sources/Notes.md")
            let root = scratch.path("root")
            #expect(SourceDiscovery.swiftFiles(under: root) == realFiles(under: root))
        }
    }

    @Test func `an excluded directory is not walked and an excluded file is dropped`() throws {
        try Scratch.with { scratch in
            try populate(scratch)
            let root = scratch.path("root")
            let found = SourceDiscovery.swiftFiles(under: root) {
                $0.hasSuffix("/Sources/") || $0.hasSuffix("/A.swift")
            }
            #expect(found.isEmpty)
        }
    }

    /// The listing gives each entry's type, so nothing is stat'ed on a file system that reports it (APFS, ext4).
    @Test func `the walk stats no entry the directory listing already typed`() throws {
        try Scratch.with { scratch in
            for index in 0..<40 { try scratch.write("root/Module\(index % 4)/File\(index).swift") }
            let discovery = SourceDiscovery.discover(under: scratch.path("root"))
            #expect(discovery.files.count == 40)
            #expect(discovery.statCalls == 0)
            #expect(discovery.unreadableDirectories.isEmpty)
        }
    }

    /// An unreadable directory contributes nothing, and says so: the analyzer can note it rather than drop it unseen.
    @Test func `an unreadable directory is reported and the rest is listed`() throws {
        try Scratch.with { scratch in
            try populate(scratch)
            try scratch.write("root/Locked/C.swift")
            let locked = scratch.path("root/Locked")
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked) }
            let root = scratch.path("root")
            let discovery = SourceDiscovery.discover(under: root)
            #expect(discovery.files == realFiles(under: root))
            #expect(discovery.unreadableDirectories == [locked])
        }
    }

    @Test func `a predicate selects other file kinds`() throws {
        try Scratch.with { scratch in
            try populate(scratch)
            try scratch.write("root/Package.swift")
            try scratch.write("root/Info.plist", "<plist/>")
            let root = scratch.path("root")
            #expect(SourceDiscovery.files(under: root, where: { $0.hasSuffix(".plist") }) == [root + "/Info.plist"])
        }
    }
}
