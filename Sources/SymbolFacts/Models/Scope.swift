//  Lifted from SwiftStaticAnalysis (MIT) — Models/Scope.swift, by way of deadwood (analyzerkit roadmap 0055).
//  Trimmed: child-links and ancestor predicates nothing here consults.

// MARK: - ScopeID

/// Unique identifier for a lexical scope.
public struct ScopeID: Sendable, Hashable, Codable {
    /// The global/file scope.
    public static let global = Self("global")

    /// The underlying identifier.
    public let id: String

    public init(_ id: String) {
        self.id = id
    }
}

// MARK: - ScopeKind

/// The kind of lexical scope.
public enum ScopeKind: String, Sendable, Codable {
    case global
    case `class`
    case `struct`
    case `enum`
    case `protocol`
    case `extension`
    case function
    case closure
    case `if`
    case `guard`
    case `for`
    case `while`
    case `switch`
    case `do`
    case actor

    /// Whether the scope is introduced by a nominal type or extension.
    public var isTypeScope: Bool {
        switch self {
        case .actor, .class, .enum, .extension, .protocol, .struct:
            true
        default:
            false
        }
    }
}

// MARK: - Scope

/// A lexical scope in the source code.
public struct Scope: Sendable, Hashable, Codable {
    /// Unique identifier for this scope.
    public let id: ScopeID

    /// The kind of scope.
    public let kind: ScopeKind

    /// Name of the scope (e.g. function name, type name).
    public let name: String?

    /// Parent scope ID (nil for global scope).
    public let parent: ScopeID?

    /// Location where the scope begins.
    public let location: SymbolLocation

    public init(
        id: ScopeID,
        kind: ScopeKind,
        name: String? = nil,
        parent: ScopeID? = nil,
        location: SymbolLocation
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.parent = parent
        self.location = location
    }
}

// MARK: - ScopeTree

/// The scope hierarchy of the analyzed sources.
public struct ScopeTree: Sendable {
    /// All scopes indexed by ID.
    public private(set) var scopes: [ScopeID: Scope] = [:]

    /// The scopes in the order they were added; a scope added again keeps its first place.
    public private(set) var ordered: [Scope] = []

    public init() {}

    /// Add a scope to the tree.
    public mutating func add(_ scope: Scope) {
        if scopes.updateValue(scope, forKey: scope.id) == nil {
            ordered.append(scope)
        } else if let index = ordered.firstIndex(where: { $0.id == scope.id }) {
            ordered[index] = scope
        }
    }

    /// Get the scope for an ID.
    public func scope(for id: ScopeID) -> Scope? {
        scopes[id]
    }

    /// Get the parent chain for a scope (nearest first).
    public func ancestors(of id: ScopeID) -> [Scope] {
        var result: [Scope] = []
        var currentID = id

        while let scope = scopes[currentID], let parentID = scope.parent {
            if let parent = scopes[parentID] {
                result.append(parent)
                currentID = parentID
            } else {
                break
            }
        }

        return result
    }

    /// The scope itself followed by its ancestors (nearest first).
    public func chain(from id: ScopeID) -> [Scope] {
        var result: [Scope] = []
        if let own = scopes[id] {
            result.append(own)
        }
        result.append(contentsOf: ancestors(of: id))
        return result
    }
}
