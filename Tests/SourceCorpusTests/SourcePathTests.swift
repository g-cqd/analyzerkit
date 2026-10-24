import Foundation
import SourceCorpus
import Testing

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
}
