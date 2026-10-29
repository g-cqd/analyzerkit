internal import AemiKernels
public import SwiftSyntax

/// Namespaces include their trailing colon, for example ["al:", "arcleak:"]. Prefix and whitespace policy belong
/// to the tool, not the grammar. The horizontal mode preserves deadwood's existing block-comment semantics.
public struct DirectiveGrammar: Sendable {
    public enum Trimming: Sendable { case whitespace, horizontal }
    private let namespaces: [String]
    private let namespaceBytes: [[UInt8]]
    private let trimming: Trimming
    private static let marker = AemiKernels.ByteSet([64])!

    public init(namespaces: [String], trimming: Trimming = .whitespace) {
        self.namespaces = namespaces.filter { !$0.isEmpty }
        namespaceBytes = self.namespaces.map { Array($0.utf8) }
        self.trimming = trimming
    }

    /// Cheap necessary condition, not directive validation: an @ followed immediately by a known prefix anywhere
    /// in the comment. Uses Aemi's runtime-dispatched ByteSet kernel over borrowed contiguous UTF-8 when possible.
    /// Comments without a marker do not allocate substrings, trim Unicode or ask a location converter for a line.
    public func containsMarker(_ comment: String) -> Bool {
        if let result = comment.utf8.withContiguousStorageIfAvailable({ bytes in
            unsafe containsMarker(bytes)
        }) {
            return result
        }
        // Non-native String storage need not expose contiguous UTF-8. Materialize only in that uncommon case.
        return Array(comment.utf8).withUnsafeBufferPointer { unsafe containsMarker($0) }
    }

    private func containsMarker(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        guard let base = bytes.baseAddress else { return false }
        var offset = 0
        while offset < bytes.count {
            // SAFETY: base comes from the borrowed buffer; the suffix pointer and count remain inside its bounds
            // for this synchronous call. The kernel returns count when there is no match. No pointer escapes.
            let found = unsafe AemiKernels.firstIndex(
                inSet: Self.marker, base: base.advanced(by: offset), count: bytes.count - offset)
            offset += found
            guard offset < bytes.count else { return false }
            let start = offset + 1
            for prefix in namespaceBytes where prefix.count <= bytes.count - start {
                var matches = true
                for index in prefix.indices where unsafe bytes[start + index] != prefix[index] {
                    matches = false
                    break
                }
                if matches { return true }
            }
            offset = start
        }
        return false
    }

    public func parse<Rule: Hashable & Sendable>(
        comment: String, line: Int, rule: (String) -> Rule?
    ) -> Directive<Rule>? {
        guard containsMarker(comment) else { return nil }
        var text = Substring(comment)
        if text.hasPrefix("//") { text = text.dropFirst(2) }
        if text.hasPrefix("/*") { text = text.dropFirst(2) }
        if text.hasSuffix("*/") { text = text.dropLast(2) }
        text = trim(text)
        guard text.hasPrefix("@") else { return nil }
        text = text.dropFirst()
        guard let namespace = namespaces.first(where: { text.hasPrefix($0) }) else { return nil }
        text = text.dropFirst(namespace.count)
        var reason: String?
        if let range = text.firstRange(of: "--") {
            reason = String(trim(text[range.upperBound...]))
            text = text[..<range.lowerBound]
        }
        let parts = text.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard let verb = parts.first else { return nil }
        let kind: DirectiveKind
        switch verb {
        case "accept": kind = .accept
        case "accept:this": kind = .acceptThis
        case "accept:next": kind = .acceptNext
        case "disable": kind = .regionDisable
        case "enable": kind = .regionEnable
        default: return nil
        }
        let words = parts.dropFirst().flatMap { $0.split(separator: ",") }
        if words.isEmpty || words.contains("all") {
            return Directive(rules: [], kind: kind, line: line, reason: reason)
        }
        let rules = words.compactMap { rule(String($0)) }
        guard !rules.isEmpty else { return nil }
        return Directive(rules: rules, kind: kind, line: line, reason: reason)
    }

    private func trim(_ text: Substring) -> Substring {
        func whitespace(_ character: Character) -> Bool {
            switch trimming {
            case .whitespace: character.isWhitespace
            case .horizontal: character == " " || character == "\t"
            }
        }
        var text = text.drop(while: whitespace)
        while let last = text.last, whitespace(last) { text = text.dropLast() }
        return text
    }

    /// One source-accurate token sweep, including inactive code, trailing trivia and EOF comments. The parser sees
    /// only comments with this grammar's marker. Doc-comment trivia is visited but its extra slash/star is not
    /// stripped by the grammar, preserving the tools' existing non-directive behavior for doc comments.
    public func scan<Result>(
        tree: SourceFileSyntax, converter: SourceLocationConverter,
        parse: (_ comment: String, _ line: Int) -> Result?
    ) -> [Result] {
        var found: [Result] = []
        func scan(_ trivia: Trivia, at start: Int) {
            var offset = start
            for piece in trivia {
                switch piece {
                case .lineComment(let comment), .blockComment(let comment),
                    .docLineComment(let comment), .docBlockComment(let comment):
                    if containsMarker(comment),
                        let directive = parse(
                            comment, converter.location(for: AbsolutePosition(utf8Offset: offset)).line)
                    {
                        found.append(directive)
                    }
                default: break
                }
                offset += piece.sourceLength.utf8Length
            }
        }
        for token in tree.tokens(viewMode: .sourceAccurate) {
            scan(token.leadingTrivia, at: token.position.utf8Offset)
            scan(token.trailingTrivia, at: token.endPositionBeforeTrailingTrivia.utf8Offset)
        }
        return found
    }
}
