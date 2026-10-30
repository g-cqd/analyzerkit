import Foundation
import SourceCorpus
import Testing

/// `SourcePath.absolute` (roadmap 0050): a path from a command line or a configuration file, made absolute against the
/// directory it is relative to, then canonical. Every tool joined these by hand; arcleak's index path skipped the
/// canonical step, so `/var/…` and `/private/var/…` were two files.
@Suite struct SourcePathAbsoluteTests {
    @Test func `a relative path is joined to its directory and made canonical`() throws {
        try Scratch.with { scratch in
            let file = try scratch.write("dir/A.swift")
            #expect(SourcePath.absolute("dir/A.swift", in: scratch.root.path) == SourcePath.canonical(file))
            #expect(SourcePath.absolute("./dir/../dir/A.swift", in: scratch.root.path) == SourcePath.canonical(file))
        }
    }

    @Test func `an absolute path ignores the directory`() throws {
        try Scratch.with { scratch in
            let file = try scratch.write("A.swift")
            #expect(SourcePath.absolute(file, in: "/somewhere/else") == SourcePath.canonical(file))
        }
    }

    /// The directory itself may be spelled through a link (the temporary directory is `/var/…` on macOS, a link to
    /// `/private/var/…`): the result is the resolved spelling, the one the compiler writes into an index store.
    @Test func `a directory spelled through a link gives the resolved spelling`() throws {
        try Scratch.with { scratch in
            let file = try scratch.write("real/A.swift")
            try scratch.link("alias", to: scratch.path("real"))
            let viaLink = SourcePath.absolute("A.swift", in: scratch.path("alias"))
            #expect(viaLink == SourcePath.canonical(file))
            #expect(!viaLink.contains("/alias/"))
        }
    }

    @Test func `an empty or dot path is the directory`() throws {
        try Scratch.with { scratch in
            let directory = SourcePath.canonical(scratch.root.path)
            #expect(SourcePath.absolute("", in: scratch.root.path) == directory)
            #expect(SourcePath.absolute(".", in: scratch.root.path) == directory)
        }
    }

    /// A tilde is a name: the shell expands it before a tool sees it, and a configuration file means a directory named so.
    @Test func `a tilde is not expanded`() {
        #expect(SourcePath.absolute("~/A.swift", in: "/d") == "/d/~/A.swift")
    }

    @Test func `the default directory is the current one`() {
        let here = FileManager.default.currentDirectoryPath
        #expect(SourcePath.absolute("Sources/A.swift") == SourcePath.absolute("Sources/A.swift", in: here))
    }
}
