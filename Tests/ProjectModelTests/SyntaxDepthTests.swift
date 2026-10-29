import ProjectModel
import SwiftParser
import SwiftSyntax
import Testing

/// Results are computed before `#expect`, which would otherwise describe the tree argument on failure: recursively.
struct SyntaxDepthTests {
    private static func chain(_ links: Int) -> SourceFileSyntax {
        Parser.parse(source: "func f() {\n let v = view" + String(repeating: ".m(1)", count: links) + "\n}\n")
    }

    @Test func `a chain far deeper than the limit is reported, on a small stack, without recursion`() {
        // 30,000 links nest about 60,000 levels; a recursive walk would overflow this test thread's stack.
        let deep = SyntaxDepth.exceeds(Self.chain(30_000))
        #expect(deep)
    }

    @Test func `ordinary code and a long but written chain are not`() {
        let chain = SyntaxDepth.exceeds(Self.chain(200))
        let nested = SyntaxDepth.exceeds(
            Parser.parse(source: "struct S {\n func f() { if a { for x in y { g(x) } } }\n}\n"))
        #expect(!chain && !nested)
    }

    @Test func `the limit is the caller's`() {
        let overFifty = SyntaxDepth.exceeds(Self.chain(200), limit: 50)
        #expect(overFifty)
    }
}
