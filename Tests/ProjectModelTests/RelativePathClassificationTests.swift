import Testing

@testable import ProjectModel

/// A path without a leading `/` (a tool's single-source entry point names its file `t.swift`) is classified by
/// conventions, and the walk over its ancestors ends. `ProjectPaths.parent` of a bare name is `.`, and of `.` is `.`
/// again: the walk stopped only at `/`, so it appended `.` until memory ran out (dolly's suites, roadmap 0020).
@Suite struct RelativePathClassificationTests {
    @Test func `the ancestors of a relative path end`() {
        #expect(ProjectClassification.ancestors(of: "t.swift") == ["t.swift", "."])
        #expect(ProjectClassification.ancestors(of: "Tests/A.swift") == ["Tests/A.swift", "Tests", "."])
        #expect(ProjectClassification.ancestors(of: ".") == ["."])
        #expect(ProjectClassification.ancestors(of: "") == [""])
        #expect(ProjectClassification.ancestors(of: "/p/A.swift") == ["/p/A.swift", "/p", "/"])
    }

    @Test func `a relative path is classified by conventions`() {
        let model = ProjectClassification.conventionsOnly
        #expect(model.classify("t.swift").region.isEmpty)
        #expect(model.classify("Tests/ATests.swift").region.contains(.test))
        #expect(model.classify("t.swift").provenance == .convention(.noProject))
    }
}
