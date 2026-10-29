public import SwiftSyntax

/// How deep a syntax tree nests, measured without recursion (analyzerkit roadmap 0041).
///
/// Every visitor, and swift-syntax's own location converter, recurses once per level of the tree. The per-file work runs
/// on a large stack (`SourceCorpus.LargeStack`), which a debug build fills at about 400,000 levels; a tree deeper than
/// ``defaultLimit`` is reported as a degraded file instead of being walked.
public enum SyntaxDepth {
    /// 20,000 levels: about 10,000 chained calls, far beyond written code, and a tenth of what the large stack holds.
    public static let defaultLimit = 20_000

    /// Whether `tree` nests deeper than `limit` levels.
    /// - Complexity: O(*n*) in the nodes visited, with an explicit stack; it stops at the first node past `limit`.
    public static func exceeds(_ tree: some SyntaxProtocol, limit: Int = defaultLimit) -> Bool {
        var pending: [(node: Syntax, depth: Int)] = [(Syntax(tree), 1)]
        while let (node, depth) = pending.popLast() {
            if depth > limit { return true }
            for child in node.children(viewMode: .sourceAccurate) { pending.append((child, depth + 1)) }
        }
        return false
    }
}
