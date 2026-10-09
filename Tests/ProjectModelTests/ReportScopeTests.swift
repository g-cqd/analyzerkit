import ProjectModel
import Testing

@Suite struct ReportScopeTests {
    @Test func `a finding is kept by its primary path`() {
        let scope = ReportScope(files: ["/project/A.swift"], canonicalize: { $0 })
        #expect(scope.contains(TestFinding(path: "/project/A.swift")))
    }

    @Test func `a finding is kept by a related path alone`() {
        let scope = ReportScope(files: ["/project/B.swift"], canonicalize: { $0 })
        let finding = TestFinding(path: "/project/A.swift", relatedPaths: ["/project/B.swift"])
        #expect(scope.contains(finding))
    }

    @Test func `a finding with no location in scope is dropped`() {
        let scope = ReportScope(files: ["/project/C.swift"], canonicalize: { $0 })
        let finding = TestFinding(path: "/project/A.swift", relatedPaths: ["/project/B.swift"])
        #expect(!scope.contains(finding))
    }

    @Test func `an empty scope keeps nothing and reports everything out of scope`() {
        let scope = ReportScope(files: [String](), canonicalize: { $0 })
        let findings = [TestFinding(path: "/project/A.swift"), TestFinding(path: "/project/B.swift")]
        #expect(scope.isEmpty)
        #expect(scope.filter(findings).inScope.isEmpty)
        #expect(scope.filter(findings).outOfScope.map(\.path) == ["/project/A.swift", "/project/B.swift"])
    }

    @Test func `entries are canonicalized the way findings are`() {
        let scope = ReportScope(files: ["./A.swift"]) { entry in
            entry.hasPrefix("./") ? String(entry.dropFirst(2)) : entry
        }
        #expect(scope.contains(TestFinding(path: "A.swift")))
    }

    @Test func `filter keeps the input order in both halves`() {
        let scope = ReportScope(files: ["/project/A.swift", "/project/C.swift"], canonicalize: { $0 })
        let findings = [
            TestFinding(path: "/project/D.swift"),
            TestFinding(path: "/project/C.swift"),
            TestFinding(path: "/project/B.swift"),
            TestFinding(path: "/project/A.swift"),
        ]
        let result = scope.filter(findings)
        #expect(result.inScope.map(\.path) == ["/project/C.swift", "/project/A.swift"])
        #expect(result.outOfScope.map(\.path) == ["/project/D.swift", "/project/B.swift"])
    }

    @Test func `a finding without related locations is kept by its path alone`() {
        let scope = ReportScope(files: ["/project/A.swift"], canonicalize: { $0 })
        #expect(scope.contains(PathOnlyFinding(path: "/project/A.swift")))
        #expect(!scope.contains(PathOnlyFinding(path: "/project/B.swift")))
    }
}

private struct TestFinding: ScopedFinding {
    var path: String
    var relatedPaths: [String] = []
}

private struct PathOnlyFinding: ScopedFinding {
    var path: String
}
