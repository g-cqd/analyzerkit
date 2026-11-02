public import SwiftSyntax

/// Lines of one file that belong to a region: `startLine...endLine`, and the exact UTF-8 byte range when the scanner
/// knows it.
public struct RegionSpan: Sendable, Hashable {
    public let startLine: Int
    public let endLine: Int
    public let region: CodeRegion
    /// The span's UTF-8 offsets in the file, from its first token to the end of its last (ADR-0030): a site on a line
    /// shared with the span but outside these bytes is not in the region. Nil for spans built from lines only.
    public let bytes: Range<Int>?

    public init(startLine: Int, endLine: Int, region: CodeRegion, bytes: Range<Int>? = nil) {
        self.startLine = startLine
        self.endLine = endLine
        self.region = region
        self.bytes = bytes
    }

    /// Lines and region, as before byte ranges were added: spans compare and hash as they always did, so the byte
    /// range is extra detail, not identity.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.startLine == rhs.startLine && lhs.endLine == rhs.endLine && lhs.region == rhs.region
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(startLine)
        hasher.combine(endLine)
        hasher.combine(region)
    }
}

/// Finds the parts of a file that only debug builds or previews compile:
/// `#if DEBUG` clauses at any depth, `#Preview` expansions, and
/// `PreviewProvider` types. Spans may nest or overlap; a line's region is
/// the union of the spans holding it (``RegionSpan/region(atLine:in:)``).
public enum CodeRegionScanner {
    /// - Complexity: O(n) in the number of syntax nodes.
    public static func scan(_ tree: SourceFileSyntax, converter: SourceLocationConverter) -> [RegionSpan] {
        let visitor = Visitor(converter: converter)
        visitor.walk(tree)
        return visitor.spans
    }

    private final class Visitor: SyntaxVisitor {
        let converter: SourceLocationConverter
        var spans: [RegionSpan] = []

        init(converter: SourceLocationConverter) {
            self.converter = converter
            super.init(viewMode: .sourceAccurate)
        }

        private func add(_ node: some SyntaxProtocol, _ region: CodeRegion) {
            let start = converter.location(for: node.positionAfterSkippingLeadingTrivia).line
            let end = converter.location(for: node.endPositionBeforeTrailingTrivia).line
            let bytes =
                node.positionAfterSkippingLeadingTrivia.utf8Offset..<node.endPositionBeforeTrailingTrivia.utf8Offset
            spans.append(RegionSpan(startLine: start, endLine: end, region: region, bytes: bytes))
        }

        override func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind {
            for clause in node.clauses where ConditionalCompilation.isDebugOnly(clause, in: node) {
                add(clause, .debugOnly)
            }
            return .visitChildren
        }

        override func visit(_ node: MacroExpansionDeclSyntax) -> SyntaxVisitorContinueKind {
            if node.macroName.text == "Preview" {
                add(node, .preview)
            }
            return .visitChildren
        }

        override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
            if node.macroName.text == "Preview" {
                add(node, .preview)
            }
            return .visitChildren
        }

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            markPreviewProvider(node, inheritance: node.inheritanceClause)
        }

        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
            markPreviewProvider(node, inheritance: node.inheritanceClause)
        }

        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
            markPreviewProvider(node, inheritance: node.inheritanceClause)
        }

        override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
            markPreviewProvider(node, inheritance: node.inheritanceClause)
        }

        private func markPreviewProvider(
            _ node: some SyntaxProtocol,
            inheritance: InheritanceClauseSyntax?
        ) -> SyntaxVisitorContinueKind {
            let names = inheritance?.inheritedTypes.map { $0.type.trimmedDescription } ?? []
            if names.contains(where: { $0 == "PreviewProvider" || $0.hasSuffix(".PreviewProvider") }) {
                add(node, .preview)
            }
            return .visitChildren
        }
    }
}

extension RegionSpan {
    /// The union of the regions of the spans holding the byte at `offset`, on line `line`: by bytes for a span that has
    /// them, by line for one that has not.
    /// - Complexity: O(s) in the number of spans.
    public static func region(atByte offset: Int, line: Int, in spans: [RegionSpan]) -> CodeRegion {
        var region = CodeRegion.production
        for span in spans {
            let holds = span.bytes.map { $0.contains(offset) } ?? (span.startLine <= line && line <= span.endLine)
            if holds { region.formUnion(span.region) }
        }
        return region
    }

    /// The union of the regions of the spans holding `line`.
    /// - Complexity: O(s) in the number of spans.
    public static func region(atLine line: Int, in spans: [RegionSpan]) -> CodeRegion {
        var region = CodeRegion.production
        for span in spans where span.startLine <= line && line <= span.endLine {
            region.formUnion(span.region)
        }
        return region
    }
}
