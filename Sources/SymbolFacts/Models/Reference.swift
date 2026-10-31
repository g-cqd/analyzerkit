//  Lifted from SwiftStaticAnalysis (MIT) — Models/Reference.swift, by way of deadwood (analyzerkit roadmap 0055).

// MARK: - ReferenceContext

/// The context in which an identifier is referenced.
public enum ReferenceContext: String, Sendable, Codable {
    /// Function or method call: `foo()`
    case call

    /// Reading a variable: `let x = foo`
    case read

    /// Writing to a variable: `foo = x`
    case write

    /// Type annotation: `let x: Foo`
    case typeAnnotation

    /// Inheritance or conformance: `class Bar: Foo`
    case inheritance

    /// Generic constraint: `where T: Foo`
    case genericConstraint

    /// Import statement: `import Foo`
    case `import`

    /// Attribute: `@Foo`
    case attribute

    /// Member access base: `foo.bar`
    case memberAccessBase

    /// Member access member: `foo.bar`
    case memberAccessMember

    /// Key path: `\Foo.bar`
    case keyPath

    /// Pattern matching: `case .foo`
    case pattern

    /// Unknown context
    case unknown
}

// MARK: - Reference

/// A reference to an identifier in source code.
public struct Reference: Sendable, Hashable, Codable {
    /// The referenced identifier.
    public let identifier: String

    /// Location of the reference.
    public let location: SymbolLocation

    /// Scope containing the reference.
    public let scope: ScopeID

    /// Context of the reference.
    public let context: ReferenceContext

    /// Whether this is a qualified reference (e.g. `Module.Type`).
    public let isQualified: Bool

    /// The qualifier if qualified (e.g. `Module` in `Module.Type`).
    public let qualifier: String?

    /// When the reference is the callee of a call with arguments, their labels in order, `_` for an unlabeled one
    /// (`location(for: x, 2)` gives `["for", "_"]`); nil otherwise. Lets a by-name match tell a function from a
    /// property of the same base name (roadmap 0058).
    public let callLabels: [String]?

    /// Where the referenced name itself is when that is not ``location``: `Inner` in the member type `Outer.Inner`,
    /// whose location is the start of `Outer`. Nil when the name is at ``location``.
    public let nameLocation: SymbolLocation?

    public init(
        identifier: String,
        location: SymbolLocation,
        scope: ScopeID,
        context: ReferenceContext,
        isQualified: Bool = false,
        qualifier: String? = nil,
        callLabels: [String]? = nil,
        nameLocation: SymbolLocation? = nil
    ) {
        self.identifier = identifier
        self.location = location
        self.scope = scope
        self.context = context
        self.isQualified = isQualified
        self.qualifier = qualifier
        self.callLabels = callLabels
        self.nameLocation = nameLocation
    }
}
