import Foundation
import ReportSupport
import Testing

@Suite struct PathPresenterTests {
    @Test func `a path inside the root loses its prefix, one outside stays absolute`() {
        let presenter = PathPresenter(root: "/repo")
        #expect(presenter.path("/repo/Sources/A.swift") == "Sources/A.swift")
        #expect(presenter.path("/other/B.swift") == "/other/B.swift")
        #expect(presenter.path("/repository/C.swift") == "/repository/C.swift")
        #expect(presenter.path("/repo") == "/repo")
        #expect(PathPresenter(root: "/repo/").path("/repo/A.swift") == "A.swift")
    }

    @Test func `free text loses the prefix wherever it quotes a path`() {
        let presenter = PathPresenter(root: "/repo")
        #expect(
            presenter.text("cycle: /repo/A.swift:3 → /repo/B.swift:4, see /other/C.swift")
                == "cycle: A.swift:3 → B.swift:4, see /other/C.swift")
        #expect(presenter.text("/repository/x") == "/repository/x")
    }
}

@Suite struct BaselineFileTests {
    private static func encoded(_ file: BaselineFile) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(file), as: UTF8.self)
    }

    @Test func `fingerprints are written sorted and unique, with or without a version`() throws {
        let versioned = BaselineFile(tool: "arcleak", fingerprints: ["b", "a", "b"], versioned: true)
        #expect(versioned.fingerprints == ["a", "b"] && versioned.version == 1)
        #expect(
            try Self.encoded(versioned)
                == "{\n  \"fingerprints\" : [\n    \"a\",\n    \"b\"\n  ],\n  \"tool\" : \"arcleak\",\n  \"version\" : 1\n}"
        )
        let bare = BaselineFile(tool: "fcheck", fingerprints: ["z"], versioned: false)
        #expect(try Self.encoded(bare) == "{\n  \"fingerprints\" : [\n    \"z\"\n  ],\n  \"tool\" : \"fcheck\"\n}")
    }

    @Test func `version 1 is accepted, another or a missing one where required is refused`() throws {
        let decoder = JSONDecoder()
        func decode(_ json: String) throws -> BaselineFile {
            try decoder.decode(BaselineFile.self, from: Data(json.utf8))
        }
        let one = try decode(#"{"fingerprints":["a"],"tool":"t","version":1}"#)
        #expect(try one.validated(requiringVersion: true) == one)
        #expect(throws: BaselineFile.Failure.unsupportedVersion(2)) {
            try decode(#"{"fingerprints":[],"tool":"t","version":2}"#).validated(requiringVersion: true)
        }
        let bare = try decode(#"{"fingerprints":["a"],"tool":"fcheck"}"#)
        #expect(try bare.validated(requiringVersion: false) == bare)
        #expect(throws: BaselineFile.Failure.missingVersion) { try bare.validated(requiringVersion: true) }
        #expect(throws: BaselineFile.Failure.unsupportedVersion(3)) {
            try decode(#"{"fingerprints":[],"tool":"t","version":3}"#).validated(requiringVersion: false)
        }
    }
}
