import Foundation
import SourceCorpus
import Synchronization
import Testing

@testable import SourceCorpus

@Suite struct SourcePathTests {
    @Test func `redundant dots and a parent round trip name the same file`() throws {
        try Scratch.with { scratch in
            let file = try scratch.write("dir/A.swift")
            let awkward = scratch.path("dir/./../dir/A.swift")
            #expect(awkward != file)
            #expect(SourcePath.canonical(awkward) == SourcePath.canonical(file))
        }
    }

    @Test func `a symlink and its target are one corpus entry`() throws {
        try Scratch.with { scratch in
            let file = try scratch.write("dir/A.swift")
            try scratch.link("Alias.swift", to: file)
            #expect(SourcePath.canonicalized([file, scratch.path("Alias.swift")]).count == 1)
        }
    }

    @Test func `canonicalizing keeps first seen order and drops repeats`() {
        #expect(
            SourcePath.canonicalized(["/b/B.swift", "/a/A.swift", "/b/./B.swift"]) == ["/b/B.swift", "/a/A.swift"])
    }

    /// A corpus is thousands of files in hundreds of directories: one full resolution per directory, not per file (the
    /// warm cache path spent 25 ms of 47 resolving maintastic's 2,980 files one by one; diary 2026-10-29-22).
    @Test func `a list is resolved once per directory, and per file only for a link`() throws {
        try Scratch.with { scratch in
            var paths: [String] = []
            for index in 0..<60 { paths.append(try scratch.write("Module\(index % 3)/F\(index).swift")) }
            try scratch.link("Module0/Alias.swift", to: scratch.path("Module1/F1.swift"))
            paths.append(scratch.path("Module0/Alias.swift"))
            let resolutions = Mutex(0)
            let result = SourcePath.canonicalized(paths) { path in
                resolutions.withLock { $0 += 1 }
                return SourcePath.canonical(path)
            }
            #expect(result == SourcePath.canonicalized(paths.map(SourcePath.canonical)))
            #expect(resolutions.withLock { $0 } <= 4, "three directories and one link")
        }
    }

    /// The shortcut must spell every file exactly as resolving it whole would: paths are hashed into fingerprints.
    @Test func `the shortcut spells every path as resolving it whole does`() throws {
        try Scratch.with { scratch in
            let real = try scratch.write("real/A.swift")
            try scratch.write("real/B.swift")
            try scratch.link("linkdir", to: scratch.path("real"))
            try scratch.link("real/Link.swift", to: real)
            try scratch.link("real/Dangling.swift", to: scratch.path("nowhere.swift"))
            let paths = [
                real, scratch.path("real/B.swift"), scratch.path("linkdir/A.swift"), scratch.path("linkdir/B.swift"),
                scratch.path("real/Link.swift"), scratch.path("real/Dangling.swift"),
                scratch.path("real/Missing.swift"),
                scratch.path("real/./../real/B.swift"), "/private" + real, "relative/Thing.swift", "/",
            ]
            let whole: [String] = paths.map(SourcePath.canonical)
            var seen: Set<String> = []
            let expected: [String] = whole.filter { seen.insert($0).inserted }
            #expect(SourcePath.canonicalized(paths) == expected)
        }
    }
}
