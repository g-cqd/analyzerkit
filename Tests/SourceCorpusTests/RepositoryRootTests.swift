import Foundation
import Testing

@testable import SourceCorpus

/// What `RepositoryRoot` answers for real trees: an ordinary clone (`.git` is a directory), a worktree or submodule (`.git`
/// is a file), a repository nested in another, and paths outside any repository.
struct RepositoryRootTests {
    private func makeRepository(_ scratch: Scratch, _ path: String, gitIsFile: Bool = false) throws {
        if gitIsFile {
            try scratch.write("\(path)/.git", "gitdir: /elsewhere\n")
        } else {
            try FileManager.default.createDirectory(
                atPath: scratch.path("\(path)/.git"), withIntermediateDirectories: true)
        }
    }

    @Test func `a file is in the nearest repository above it, whether .git is a directory or a file`() throws {
        try Scratch.with { scratch in
            try makeRepository(scratch, "clone")
            try makeRepository(scratch, "worktree", gitIsFile: true)
            let inClone = try scratch.write("clone/Sources/Module/A.swift")
            let inWorktree = try scratch.write("worktree/B.swift")
            #expect(RepositoryRoot.detect(from: inClone) == scratch.path("clone"))
            #expect(RepositoryRoot.detect(from: inWorktree) == scratch.path("worktree"))
        }
    }

    @Test func `a repository nested in another is the root of the files below it`() throws {
        try Scratch.with { scratch in
            try makeRepository(scratch, "outer")
            try makeRepository(scratch, "outer/vendor/inner", gitIsFile: true)
            let inner = try scratch.write("outer/vendor/inner/Sources/C.swift")
            let outer = try scratch.write("outer/vendor/D.swift")
            #expect(RepositoryRoot.detect(from: inner) == scratch.path("outer/vendor/inner"))
            #expect(RepositoryRoot.detect(from: outer) == scratch.path("outer"))
        }
    }

    @Test func `a path outside any repository has no root`() throws {
        try Scratch.with { scratch in
            let loose = try scratch.write("loose/E.swift")
            #expect(RepositoryRoot.detect(from: loose) == nil)
        }
    }

    @Test func `a directory written with a trailing slash-dot is searched from itself`() throws {
        try Scratch.with { scratch in
            try makeRepository(scratch, "clone")
            #expect(RepositoryRoot.detect(from: scratch.path("clone") + "/.") == scratch.path("clone"))
        }
    }

    @Test func `a corpus has a common root only when every file shares one`() throws {
        try Scratch.with { scratch in
            try makeRepository(scratch, "one")
            try makeRepository(scratch, "two")
            let a = try scratch.write("one/a/A.swift")
            let b = try scratch.write("one/b/c/B.swift")
            let c = try scratch.write("two/C.swift")
            let loose = try scratch.write("loose/D.swift")
            #expect(RepositoryRoot.common(of: [a, b]) == scratch.path("one"))
            #expect(RepositoryRoot.common(of: [a, c]) == nil, "two repositories")
            #expect(RepositoryRoot.common(of: [a, loose]) == nil, "one file outside")
            #expect(RepositoryRoot.common(of: []) == nil)
        }
    }

    @Test func `a corpus probes each directory for .git once, not once per file`() {
        // 1,000 files in 10 directories of one repository, three levels below its root.
        let corpus = (0..<10).flatMap { directory in
            (0..<100).map { "/repository/Sources/Module\(directory)/File\($0).swift" }
        }
        var probes = 0
        let root = RepositoryRoot.common(of: corpus) { path in
            probes += 1
            return path == "/repository/.git"
        }
        #expect(root == "/repository")
        // Module0, Sources and the root once, then one new module directory per other module.
        #expect(probes <= 10 + 3, "\(probes) probes for 10 directories")
    }

    @Test func `a path is made relative to its root, and left alone outside it`() {
        #expect(RepositoryRoot.relativize("/r/Sources/A.swift", to: "/r") == "Sources/A.swift")
        #expect(RepositoryRoot.relativize("/r/Sources/A.swift", to: "/r/") == "Sources/A.swift")
        #expect(RepositoryRoot.relativize("/rx/A.swift", to: "/r") == "/rx/A.swift")
    }
}
