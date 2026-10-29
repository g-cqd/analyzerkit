// Copy into arcleak/Tests/ArcLeakCoreTests/ZZSuppressionPerfTests.swift, then run:
// swift test -c release -Xswiftc -enable-testing --filter suppressionReleaseProbe
// Remove the throwaway test afterward. Legacy grammar/scanner from arcleak cb1bb82, before roadmap 0012 adoption.
import Foundation
import SwiftParser
import SwiftSyntax
import Testing

@testable import ArcLeakCore

struct LegacySuppressionDirective: Sendable, Equatable, Codable {
    enum Kind: Sendable, Equatable, Codable {
        case acceptThis
        case acceptNext
        /// `@al:accept` — covers its own line *and* the next, so it works both
        /// as a trailing comment and on the line above the flagged code.
        case accept
        case regionDisable
        case regionEnable
    }

    /// The accepted namespace prefixes after the `@` sigil.
    static let namespaces = ["al:", "arcleak:"]

    /// Empty set means "all rules".
    let rules: Set<RuleID>
    let kind: Kind
    /// 1-based line the comment appears on.
    let line: Int
    let reason: String?

    init(rules: Set<RuleID>, kind: Kind, line: Int, reason: String?) {
        self.rules = rules
        self.kind = kind
        self.line = line
        self.reason = reason
    }

    func covers(_ rule: RuleID) -> Bool {
        rules.isEmpty || rules.contains(rule)
    }

    /// Parses one comment. Returns nil when it isn't an `@al:`/`@arcleak:`
    /// directive. Unknown rule ids inside a directive are ignored (they may
    /// belong to a future version) — but if a rule-scoped verb names *only*
    /// unknown rules, the directive suppresses nothing rather than everything.
    static func parse(comment: String, line: Int) -> LegacySuppressionDirective? {
        var text = comment
        if text.hasPrefix("//") { text.removeFirst(2) }
        if text.hasPrefix("/*") { text.removeFirst(2) }
        if text.hasSuffix("*/") { text.removeLast(2) }
        text = String(
            text.drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed())

        guard text.hasPrefix("@") else { return nil }
        text.removeFirst()
        guard let namespace = namespaces.first(where: text.hasPrefix) else { return nil }
        text.removeFirst(namespace.count)

        var reason: String?
        if let range = text.firstRange(of: "--") {
            reason = String(
                text[range.upperBound...].drop(while: \.isWhitespace)
                    .reversed().drop(while: \.isWhitespace).reversed())
            text = String(text[..<range.lowerBound])
        }
        let parts = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let verb = parts.first else { return nil }
        let ruleWords = parts.dropFirst().flatMap { $0.split(separator: ",").map(String.init) }

        let kind: Kind
        switch verb {
        case "accept": kind = .accept
        case "accept:this": kind = .acceptThis
        case "accept:next": kind = .acceptNext
        case "disable": kind = .regionDisable
        case "enable": kind = .regionEnable
        default: return nil
        }

        if ruleWords.contains("all") || ruleWords.isEmpty {
            return LegacySuppressionDirective(rules: [], kind: kind, line: line, reason: reason)
        }
        let rules = Set(ruleWords.compactMap(RuleID.init(rawValue:)))
        guard !rules.isEmpty else { return nil }
        return LegacySuppressionDirective(rules: rules, kind: kind, line: line, reason: reason)
    }
}

private func legacyScan(tree: SourceFileSyntax, converter: SourceLocationConverter) -> [LegacySuppressionDirective] {
    var directives: [LegacySuppressionDirective] = []

    func scan(_ trivia: Trivia, startingAt startOffset: Int) {
        var offset = startOffset
        for piece in trivia {
            switch piece {
            case .lineComment(let text), .blockComment(let text),
                .docLineComment(let text), .docBlockComment(let text):
                let line = converter.location(for: AbsolutePosition(utf8Offset: offset)).line
                if let directive = LegacySuppressionDirective.parse(comment: text, line: line) {
                    directives.append(directive)
                }
            default:
                break
            }
            offset += piece.sourceLength.utf8Length
        }
    }

    for token in tree.tokens(viewMode: .sourceAccurate) {
        scan(token.leadingTrivia, startingAt: token.position.utf8Offset)
        scan(token.trailingTrivia, startingAt: token.endPositionBeforeTrailingTrivia.utf8Offset)
    }
    return directives
}

@Test func suppressionReleaseProbe() {
    let source =
        (0..<20000).map { index in
            index % 1000 == 0
                ? "// @al:accept -- reviewed \(index)\n"
                : "// ordinary prose café documentation \(index) with no directive\n"
        }.joined() + "let value = 1\n"
    let tree = Parser.parse(source: source)
    let converter = SourceLocationConverter(fileName: "Probe.swift", tree: tree)
    var before: [Double] = []
    var after: [Double] = []
    var total = 0
    for round in 0..<5 {
        func old() {
            let start = Date()
            let directives = legacyScan(tree: tree, converter: converter)
            before.append(Date().timeIntervalSince(start))
            total += directives.count
        }
        func new() {
            let start = Date()
            let directives = FactsExtraction.scanDirectives(tree: tree, converter: converter)
            after.append(Date().timeIntervalSince(start))
            total += directives.count
        }
        if round % 2 == 0 { old(); new() } else { new(); old() }
    }
    let legacy = legacyScan(tree: tree, converter: converter)
    let shared = FactsExtraction.scanDirectives(tree: tree, converter: converter)
    #expect(total == 200)
    #expect(legacy.map(\.line) == shared.map(\.line))
    #expect(legacy.map(\.reason) == shared.map(\.reason))
    #expect(legacy.map(\.rules) == shared.map(\.rules))
    print("SUPPRESSION-RELEASE old median=\(before.sorted()[2]) samples=\(before)")
    print("SUPPRESSION-RELEASE new median=\(after.sorted()[2]) samples=\(after)")
}
