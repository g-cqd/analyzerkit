import AemiProtobuf
import SwiftParser
import SwiftSyntax
import SymbolFacts
import Testing

/// The facts of `source`, parsed as written (unfolded), as the file `F.swift`.
private func facts(_ source: String) -> FileSymbolFacts {
    let tree = Parser.parse(source: source)
    return FileSymbolFacts.collect(
        tree: tree, file: "F.swift", converter: SourceLocationConverter(fileName: "F.swift", tree: tree))
}

/// What deadwood's collectors gave for ``fixture`` at deadwood `c2b1229` (roadmap 0055's probe): a `D` row per
/// declaration, imports last, and an `R` row per reference, each with its line, column, name and kind or context.
private let deadwoodRows = """
    D	4	1	Shape	protocol
    D	6	5	area	variable
    D	9	1	Square	struct
    D	10	5	side	variable
    D	11	5	unit	constant
    D	12	5	area	variable
    D	14	5	init	initializer
    D	14	10	side	parameter
    D	18	5	grow	method
    D	18	24	amount	parameter
    D	18	43	times	parameter
    D	21	9	total	constant
    D	27	1	Direction	enum
    D	28	10	north	enumCase
    D	28	17	south	enumCase
    D	31	1	Outer.Inner	extension
    D	32	5	Pair	typealias
    D	33	5	subscript	subscript
    D	33	15	index	parameter
    D	36	1	Box	class
    D	37	5	deinit	deinitializer
    D	38	5	call	method
    D	41	1	Counter	actor
    D	43	1	<=>	operator
    D	1	1	Foundation	import
    R	4	2	MainActor	attribute
    R	4	2	MainActor	typeAnnotation
    R	5	24	Sendable	typeAnnotation
    R	6	15	Double	typeAnnotation
    R	9	23	Shape	typeAnnotation
    R	9	30	Codable	typeAnnotation
    R	10	6	State	attribute
    R	10	6	State	typeAnnotation
    R	10	30	Double	typeAnnotation
    R	11	30	Square	call
    R	12	22	Double	typeAnnotation
    R	12	31	side	unknown
    R	12	38	side	unknown
    R	14	16	Double	typeAnnotation
    R	15	9	self	memberAccessBase
    R	15	14	side	memberAccessMember
    R	15	21	side	unknown
    R	18	35	Double	typeAnnotation
    R	18	52	Int	typeAnnotation
    R	18	76	Double	typeAnnotation
    R	19	9	side	unknown
    R	19	17	amount	unknown
    R	20	9	side	unknown
    R	20	16	side	unknown
    R	21	21	times	memberAccessBase
    R	21	27	reduce	memberAccessMember
    R	21	37	+	unknown
    R	22	24	times	memberAccessBase
    R	22	30	first	memberAccessMember
    R	22	38	print	call
    R	22	44	first	unknown
    R	22	51	total	unknown
    R	23	16	area	unknown
    R	27	17	String	typeAnnotation
    R	27	25	CaseIterable	typeAnnotation
    R	31	11	Outer	typeAnnotation
    R	31	11	Inner	typeAnnotation
    R	31	29	Element	typeAnnotation
    R	31	38	Hashable	typeAnnotation
    R	32	23	Outer	typeAnnotation
    R	32	23	Inner	typeAnnotation
    R	32	36	Int	typeAnnotation
    R	33	22	Int	typeAnnotation
    R	33	30	Int	typeAnnotation
    R	33	36	index	unknown
    R	38	23	selector	call
    R	38	33	Box	memberAccessBase
    R	38	37	call	memberAccessMember
    """

private let fixture = """
    import Foundation

    /// A shape.
    @MainActor
    public protocol Shape: Sendable {
        var area: Double { get }
    }

    public struct Square: Shape, Codable {
        @State private var side: Double = 1
        public static let unit = Square()
        public var area: Double { side * side }

        init(side: Double = 1) {
            self.side = side
        }

        mutating func grow(by amount: Double, _ times: Int...) async throws -> Double {
            side += amount
            side = side * 2
            let total = times.reduce(0, +)
            if let first = times.first { print(first, total) }
            return area
        }
    }

    enum Direction: String, CaseIterable {
        case north, south
    }

    extension Outer.Inner where Element: Hashable {
        typealias Pair = (Outer.Inner, Int)
        subscript(index: Int) -> Int { index }
    }

    final class Box<T> {
        deinit {}
        func call() { _ = #selector(Box.call) }
    }

    actor Counter {}

    infix operator <=>
    """

@Suite struct SymbolFactsTests {
    @Test func `the declarations and references are deadwood's, apart from what this library adds`() {
        let found = facts(fixture)
        let rows =
            (found.declarations + found.imports).filter { $0.kind != .macro }.map {
                "D\t\($0.location.line)\t\($0.location.column)\t\($0.name)\t\($0.kind.rawValue)"
            }
            + found.references.map {
                "R\t\($0.location.line)\t\($0.location.column)\t\($0.identifier)\t\($0.context.rawValue)"
            }
        #expect(rows.joined(separator: "\n") == deadwoodRows)
    }

    @Test func `a declaration's name is placed at the name, after its attributes and modifiers`() throws {
        let found = facts("@MainActor\npublic final class Model {\n  @State private var count = 0\n}")
        let model = try #require(found.declarations.first { $0.name == "Model" })
        #expect((model.location.line, model.location.column) == (1, 1))
        #expect((model.nameLocation.line, model.nameLocation.column) == (2, 20))
        let count = try #require(found.declarations.first { $0.name == "count" })
        #expect((count.nameLocation.line, count.nameLocation.column) == (3, 23))
    }

    @Test func `the names of an initializer, a subscript, an extension and an import are their first token`() throws {
        let found = facts(
            "import Foo.Bar\nextension Outer.Inner {\n  public init() {}\n  subscript(i: Int) -> Int { i }\n}")
        func name(_ text: String) throws -> (Int, Int) {
            let declaration = try #require((found.declarations + found.imports).first { $0.name == text })
            return (declaration.nameLocation.line, declaration.nameLocation.column)
        }
        #expect(try name("Foo.Bar") == (1, 8))
        #expect(try name("Outer.Inner") == (2, 11))
        #expect(try name("init") == (3, 10))
        #expect(try name("subscript") == (4, 3))
    }

    @Test func `a macro declaration is recorded, with its signature`() throws {
        let found = facts(
            "@freestanding(expression)\npublic macro stringify<T>(_ value: T) -> (T, String) = #externalMacro(module: \"M\", type: \"S\")"
        )
        let macro = try #require(found.declarations.first { $0.kind == .macro })
        #expect(macro.name == "stringify")
        #expect(macro.accessLevel == .public)
        #expect(macro.genericParameters == ["T"])
        #expect(macro.signature?.parameters.map(\.name) == ["value"])
        #expect((macro.nameLocation.line, macro.nameLocation.column) == (2, 14))
    }

    @Test func `a member type's last component is placed at its own name`() throws {
        let found = facts("let x: Outer.Inner = y")
        let inner = try #require(found.references.first { $0.identifier == "Inner" })
        #expect(inner.qualifier == "Outer")
        #expect((inner.location.line, inner.location.column) == (1, 8))
        #expect(inner.nameLocation.map { ($0.line, $0.column) } ?? (0, 0) == (1, 14))
        let outer = try #require(found.references.first { $0.identifier == "Outer" })
        #expect(outer.nameLocation == nil)
    }

    @Test func `the scopes come in the order the walk opens them`() {
        let found = facts("struct A {\n  func f() { if x {} }\n}\nenum B {}")
        #expect(found.scopes.map(\.kind) == [.global, .struct, .function, .if, .enum])
        #expect(found.scopes.map(\.parent) == [nil, .global, found.scopes[1].id, found.scopes[2].id, .global])
    }

    @Test func `the facts survive the protobuf payload whole`() throws {
        let found = facts(fixture + "\n// commented Ghost\nlet s = \"LegacyName\"\n")
        let bytes = try ProtobufEncoder().encodeToBytes(found)
        let decoded = try ProtobufDecoder().decode(FileSymbolFacts.self, fromBytes: bytes)
        #expect(decoded == found)
        #expect(decoded.commentTokens.contains("Ghost"))
        #expect(decoded.stringLiteralTokens.contains(TokenLine(token: "LegacyName", line: 45)))
    }
}
