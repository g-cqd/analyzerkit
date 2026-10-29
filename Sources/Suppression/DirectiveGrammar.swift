public import SwiftSyntax

/// Namespaces include their trailing colon, for example ["al:", "arcleak:"].
public struct DirectiveGrammar: Sendable {
    public enum Trimming: Sendable { case whitespace, horizontal }
    public init(namespaces: [String], trimming: Trimming = .whitespace) {}
    public func containsMarker(_ comment: String) -> Bool { false }
    public func parse<Rule: Hashable & Sendable>(
        comment: String, line: Int, rule: (String) -> Rule?
    ) -> Directive<Rule>? { nil }

    /// The callback seam counts grammar invocations independently from comment enumeration.
    public func scan<Result>(
        tree: SourceFileSyntax, converter: SourceLocationConverter,
        parse: (_ comment: String, _ line: Int) -> Result?
    ) -> [Result] { [] }
}
