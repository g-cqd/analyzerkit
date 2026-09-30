import ProjectModel
import SwiftParser
import Testing

@Suite struct TestConventionsTests {
    @Test(arguments: [
        ("Sources/Sample/Model.swift", "import XCTest\nfinal class ModelChecks: XCTestCase {}\n"),
        ("Sources/Sample/Model.swift", "@testable import Sample\nimport Testing\n"),
        ("SampleUnitTests/Mocks/SampleMock.swift", "final class SampleMock {}\n"),
        ("Sample/Tests/SampleFixtures.swift", "enum SampleFixtures {}\n"),
        ("Sample/SampleTests.swift", "enum Sample {}\n"),
    ])
    func `test code is recognized by its imports or its path`(path: String, source: String) {
        #expect(TestConventions.isTestFile(path: path, tree: Parser.parse(source: source)))
    }

    @Test func `production code is not test code`() {
        let tree = Parser.parse(source: "import Foundation\nstruct Contest {}\n")

        #expect(!TestConventions.isTestFile(path: "Sources/Sample/Contest.swift", tree: tree))
        #expect(!TestConventions.isTestFile(path: "Sources/Sample/Tests.md.swift", tree: tree))
    }
}
