import ReportSupport
import Testing

@Suite struct ArtifactURITests {
    @Test func `a plain relative path stays relative and names the base when there is one`() {
        #expect(ArtifactURI.location(of: "Sources/A.swift", root: "/repo").uri == "Sources/A.swift")
        #expect(ArtifactURI.location(of: "Sources/A.swift", root: "/repo").uriBaseId == "SRCROOT")
        #expect(ArtifactURI.location(of: "Sources/A.swift", root: nil).uriBaseId == nil)
    }

    @Test func `an absolute path becomes a percent-encoded file URI`() {
        let location = ArtifactURI.location(of: "/Users/me/My Repo/Box#1.swift", root: nil)
        #expect(location.uri == "file:///Users/me/My%20Repo/Box%231.swift" && location.uriBaseId == nil)
    }

    @Test func `a relative path that needs escapes is anchored to the root as an absolute URI`() {
        #expect(ArtifactURI.location(of: "My Dir/A.swift", root: "/repo").uri == "file:///repo/My%20Dir/A.swift")
        #expect(ArtifactURI.location(of: "My Dir/A.swift", root: nil).uri == "My%20Dir/A.swift")
    }

    @Test func `non-ASCII bytes are escaped in upper-case hexadecimal and the base URI ends in a slash`() {
        #expect(ArtifactURI.percentEncoded("é") == "%C3%A9")
        #expect(ArtifactURI.percentEncoded("\u{1}") == "%01")
        #expect(ArtifactURI.baseURI(of: "/repo") == "file:///repo/")
        #expect(ArtifactURI.baseURI(of: "/repo/") == "file:///repo/")
    }
}
