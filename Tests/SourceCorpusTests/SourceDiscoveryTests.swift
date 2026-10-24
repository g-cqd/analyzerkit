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

    @Test func `a link inside the root is followed and its files are listed once`() throws {
        try Scratch.with { scratch in
            try populate(scratch)
            try scratch.link("root/Alias", to: "Sources")
            let root = scratch.path("root")
            let files = SourceDiscovery.swiftFiles(under: root)
            #expect(files.count == 2)
            #expect(Set(SourcePath.canonicalized(files)) == Set(SourcePath.canonicalized(realFiles(under: root))))
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
