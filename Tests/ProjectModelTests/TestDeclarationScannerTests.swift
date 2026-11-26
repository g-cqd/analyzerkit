import ProjectModel
import SwiftParser
import SwiftSyntax
import Testing

@Suite struct TestDeclarationScannerTests {
    private func scan(_ source: String) -> [TestDeclaration] {
        let tree = Parser.parse(source: source)
        return TestDeclarationScanner.scan(tree, converter: SourceLocationConverter(fileName: "T.swift", tree: tree))
    }

    @Test func `Swift Testing functions are found with their suite and line span, at any depth`() {
        let found = scan(
            """
            import Testing
            @Test func global() {
                #expect(true)
            }
            @Suite struct Outer {
                @Test("named") func first() {}
                struct Inner {
                    @Test(.tags(.fast)) func second(value: Int) async throws {}
                }
                func helper() {}
            }
            """
        )
        #expect(found.map(\.name) == ["global", "first", "second"])
        #expect(found.map(\.suite) == [nil, "Outer", "Outer.Inner"])
        #expect(found.map(\.lines) == [2...4, 6...6, 8...8])
        #expect(found.allSatisfy { $0.framework == .swiftTesting })
        #expect(found[2].signature == "second(value:)")
    }

    @Test func `XCTest methods are the parameterless test methods of an XCTestCase subclass`() {
        let found = scan(
            """
            import XCTest
            final class LimitTests: XCTestCase {
                func testBoundary() { XCTAssertTrue(true) }
                func testWithArgument(_ x: Int) {}
                func helperTest() {}
                static func testStatic() {}
            }
            final class NotATestCase {
                func testNothing() {}
            }
            """
        )
        #expect(found.map(\.name) == ["testBoundary"])
        #expect(found.first?.suite == "LimitTests" && found.first?.framework == .xcTest)
    }

    @Test func `a test declaration overlapping changed lines is found by line`() {
        let found = scan("import Testing\n@Test func a() {}\n\n@Test func b() {\n  #expect(1 == 1)\n}\n")
        #expect(found.filter { $0.lines.overlaps(5...5) }.map(\.name) == ["b"])
    }
}
