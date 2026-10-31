public import SwiftSyntax

/// What one file declares and references, with the lexical scopes between (roadmap 0055).
///
/// Every declaration is recorded, locals and parameters included, at the position after its leading trivia, with
/// ``Declaration/nameLocation`` at the name. A reference's context comes from the syntax around it: fold the tree's
/// operators first (SwiftOperators) for an assignment to read as ``ReferenceContext/write``.
public struct FileSymbolFacts: Sendable, Hashable, Codable {
    /// The path the facts describe, as the locations spell it.
    public let file: String

    /// The declarations, imports excepted, in source order.
    public let declarations: [Declaration]

    /// The imports, in source order.
    public let imports: [Declaration]

    /// The references, in the order the walk meets them.
    public let references: [Reference]

    /// The scopes, the file scope (``ScopeID/global``) first, in the order the walk opens them.
    public let scopes: [Scope]

    /// The identifier-shaped tokens of the string literals, with their lines: names a program may reach dynamically.
    public let stringLiteralTokens: Set<TokenLine>

    /// The identifier-shaped tokens of the `//` and `/* */` comments, documentation comments excepted.
    public let commentTokens: Set<String>

    public init(
        file: String,
        declarations: [Declaration],
        imports: [Declaration] = [],
        references: [Reference],
        scopes: [Scope],
        stringLiteralTokens: Set<TokenLine> = [],
        commentTokens: Set<String> = []
    ) {
        self.file = file
        self.declarations = declarations
        self.imports = imports
        self.references = references
        self.scopes = scopes
        self.stringLiteralTokens = stringLiteralTokens
        self.commentTokens = commentTokens
    }

    /// The facts of `tree`, the file at `file`, whose locations `converter` gives.
    /// - Complexity: O(*n*) in the size of the tree; two walks.
    public static func collect(tree: SourceFileSyntax, file: String, converter: SourceLocationConverter) -> Self {
        let declarations = DeclarationCollector(file: file, converter: converter)
        declarations.walk(tree)
        let references = ReferenceCollector(file: file, converter: converter)
        references.walk(tree)
        return Self(
            file: file, declarations: declarations.declarations, imports: declarations.imports,
            references: references.references, scopes: declarations.tracker.tree.ordered,
            stringLiteralTokens: references.stringLiteralTokens, commentTokens: references.commentTokens)
    }
}
