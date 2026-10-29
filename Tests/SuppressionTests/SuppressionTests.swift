import Suppression
import SwiftParser
import SwiftSyntax
import Testing

@Suite struct SuppressionTests {
    private enum Rule: String, Hashable, Sendable { case first, second }
    private static let prefixes = [
        ["al:", "arcleak:"], ["dw:", "deadwood:"], ["dl:", "dolly:"], ["fc:", "fcheck:"],
    ]

    @Test(arguments: prefixes)
    func `all tool grammars preserve verbs aliases rule lists and reasons`(_ prefixes: [String]) throws {
        let grammar = DirectiveGrammar(namespaces: prefixes)
        for prefix in prefixes {
            for (verb, kind) in [
                ("accept", DirectiveKind.accept), ("accept:this", .acceptThis),
                ("accept:next", .acceptNext), ("disable", .regionDisable), ("enable", .regionEnable),
            ] {
                let directive = try #require(
                    grammar.parse(
                        comment: "// @\(prefix)\(verb) first, second unknown first -- reviewed -- deliberately",
                        line: 10,
                        rule: Rule.init(rawValue:)))
                #expect(directive.kind == kind)
                #expect(directive.rules == [.first, .second, .first])
                #expect(directive.line == 10)
                #expect(directive.reason == "reviewed -- deliberately")
            }
            for suffix in ["", " all", " unknown,all", " ,,,"] {
                let directive = try #require(
                    grammar.parse(comment: "/* @\(prefix)accept\(suffix) */", line: 1, rule: Rule.init(rawValue:)))
                #expect(directive.rules.isEmpty)
                #expect(directive.covers(.first))
            }
            for comment in [
                "// ordinary", "// #\(prefix)accept", "// \(prefix)accept", "// @other:accept",
                "// @\(prefix)acept", "// prose @\(prefix)accept", "/// @\(prefix)accept", "/** @\(prefix)accept */",
                "// @\(prefix)accept unknown",
            ] {
                #expect(grammar.parse(comment: comment, line: 1, rule: Rule.init(rawValue:)) == nil)
            }
            let emptyReason = try #require(
                grammar.parse(comment: "// @\(prefix)accept --  ", line: 1, rule: Rule.init(rawValue:)))
            #expect(emptyReason.reason == "")
        }
    }

    @Test func `horizontal trimming preserves deadwoods multiline block comment semantics`() {
        let comment = "/*\n @dw:accept first -- reason\n*/"
        let horizontal = DirectiveGrammar(namespaces: ["dw:"], trimming: .horizontal)
        let whitespace = DirectiveGrammar(namespaces: ["dw:"])
        #expect(horizontal.parse(comment: comment, line: 1, rule: Rule.init(rawValue:)) == nil)
        #expect(whitespace.parse(comment: comment, line: 1, rule: Rule.init(rawValue:))?.reason == "reason")
    }

    @Test(arguments: prefixes)
    func `byte prefilter never invokes the parser for comments without a known marker`(_ prefixes: [String]) {
        let p = prefixes[0]
        let source = """
            // ordinary comment
            // café 🎉 \(String(repeating: "no directive ", count: 1000))
            // #\(p)expect first
            // @foreign:accept
            let text = "// @\(p)accept"
            /* @\(p)disable first -- region */
            let value = 1 // @\(prefixes[1])accept:next second
            // @\(p)enable first
            """
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: "Test.swift", tree: tree)
        let grammar = DirectiveGrammar(namespaces: prefixes)
        var calls = 0
        let directives = grammar.scan(tree: tree, converter: converter) { comment, line in
            calls += 1
            return grammar.parse(comment: comment, line: line, rule: Rule.init(rawValue:))
        }
        #expect(calls == 3)
        #expect(directives.map(\.line) == [6, 7, 8])
        #expect(directives.map(\.kind) == [.regionDisable, .acceptNext, .regionEnable])
        #expect(!grammar.containsMarker("// @"))
        #expect(!grammar.containsMarker("// @foreign:accept"))
        #expect(grammar.containsMarker("// not a directive but contains @\(p)accept"))
    }

    @Test func `trivia offsets count UTF8 CRLF block comments and EOF accurately`() {
        let source =
            "let café = 1 /* @al:accept:this first */\r\n/* @al:accept:next second */\r\nlet b = 2\r\n// @al:disable -- eof"
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: "Test.swift", tree: tree)
        let grammar = DirectiveGrammar(namespaces: ["al:"])
        let directives = grammar.scan(tree: tree, converter: converter) {
            grammar.parse(comment: $0, line: $1, rule: Rule.init(rawValue:))
        }
        #expect(directives.map(\.line) == [1, 2, 4])
        #expect(directives.last?.reason == "eof")
    }

    @Test func `table preserves line coverage region precedence and double optional reasons`() throws {
        typealias D = Directive<Rule>
        let table = SuppressionTable(directives: [
            D(rules: [.first], kind: .regionEnable, line: 30, reason: nil),
            D(rules: [], kind: .regionDisable, line: 3, reason: "region"),
            D(rules: [], kind: .acceptThis, line: 5, reason: nil),
            D(rules: [.second], kind: .acceptNext, line: 10, reason: "next"),
            D(rules: [], kind: .accept, line: 20, reason: "accept"),
        ])
        #expect(table.suppression(for: .first, line: 2) == nil)
        #expect(table.suppression(for: .first, line: 3) == .some("region"))
        let withoutReason = table.suppression(for: .first, line: 5)
        #expect(withoutReason != nil)
        #expect(try #require(withoutReason) == nil)
        #expect(table.suppression(for: .first, line: 6) == .some("region"))
        #expect(table.suppression(for: .second, line: 11) == .some("next"))
        for line in [20, 21] { #expect(table.suppression(for: .first, line: line) == .some("accept")) }
        #expect(table.suppression(for: .first, line: 22) == .some("region"))
        #expect(table.suppression(for: .first, line: 30) == nil)
        #expect(table.suppression(for: .second, line: 9999) == .some("region"))
    }

    @Test func `same line order and non-nested disable enable behavior stay stable`() {
        typealias D = Directive<Rule>
        let table = SuppressionTable(directives: [
            D(rules: [], kind: .regionDisable, line: 1, reason: "outer"),
            D(rules: [], kind: .regionDisable, line: 2, reason: "inner"),
            D(rules: [], kind: .regionEnable, line: 3, reason: nil),
            D(rules: [], kind: .acceptThis, line: 4, reason: "first"),
            D(rules: [], kind: .acceptThis, line: 4, reason: "second"),
        ])
        #expect(table.suppression(for: .first, line: 2) == .some("inner"))
        #expect(table.suppression(for: .first, line: 3) == nil)
        #expect(table.suppression(for: .first, line: 4) == .some("first"))
    }
}
