//  Lifted from SwiftStaticAnalysis (MIT) — Models/Declaration.swift, by way of deadwood (analyzerkit roadmap 0055).
//  Trimmed: `swa:ignore` directive plumbing and display helpers. Added: macro declarations and the name's position.

// MARK: - DeclarationKind

/// The kind of declaration.
public enum DeclarationKind: String, Sendable, CaseIterable, Codable {
    case function
    case method
    case initializer
    case deinitializer
    case variable
    case constant
    case parameter
    case `class`
    case `struct`
    case `enum`
    case `protocol`
    case `extension`
    case `typealias`
    case `associatedtype`
    case `import`
    case `subscript`
    case `operator`
    case enumCase
    case actor
    /// A macro declaration: `macro stringify(_:)`.
    case macro
    /// File-scope code that is not a declaration (`#Preview`, script statements): a node a consumer synthesizes; the
    /// collector never records one.
    case topLevelCode
}

// MARK: - AccessLevel

/// Swift access level modifiers, ordered from most to least restrictive.
public enum AccessLevel: String, Sendable, Comparable, CaseIterable, Codable {
    case `private`
    case `fileprivate`
    case `internal`
    case package
    case `public`
    case open

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .private: 0
        case .fileprivate: 1
        case .internal: 2
        case .package: 3
        case .public: 4
        case .open: 5
        }
    }
}

// MARK: - DeclarationModifiers

/// Modifiers that can be applied to declarations.
public struct DeclarationModifiers: OptionSet, Sendable, Hashable, Codable {
    public static let `static` = Self(rawValue: 1 << 0)
    public static let `class` = Self(rawValue: 1 << 1)
    public static let final = Self(rawValue: 1 << 2)
    public static let override = Self(rawValue: 1 << 3)
    public static let mutating = Self(rawValue: 1 << 4)
    public static let nonmutating = Self(rawValue: 1 << 5)
    public static let lazy = Self(rawValue: 1 << 6)
    public static let weak = Self(rawValue: 1 << 7)
    public static let unowned = Self(rawValue: 1 << 8)
    public static let optional = Self(rawValue: 1 << 9)
    public static let required = Self(rawValue: 1 << 10)
    public static let convenience = Self(rawValue: 1 << 11)
    public static let nonisolated = Self(rawValue: 1 << 12)
    public static let consuming = Self(rawValue: 1 << 13)
    public static let borrowing = Self(rawValue: 1 << 14)

    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

// MARK: - FunctionSignature

/// A function or method signature.
public struct FunctionSignature: Sendable, Hashable, Codable {
    /// A single parameter in a function signature.
    public struct Parameter: Sendable, Hashable, Codable {
        /// External parameter label (nil for unlabeled).
        public let label: String?

        /// Internal parameter name.
        public let name: String

        /// Parameter type as source text.
        public let type: String

        /// Whether the parameter has a default value.
        public let hasDefaultValue: Bool

        /// Whether the parameter is variadic.
        public let isVariadic: Bool

        /// Whether the parameter is `inout`.
        public let isInout: Bool

        public init(
            label: String?,
            name: String,
            type: String,
            hasDefaultValue: Bool = false,
            isVariadic: Bool = false,
            isInout: Bool = false
        ) {
            self.label = label
            self.name = name
            self.type = type
            self.hasDefaultValue = hasDefaultValue
            self.isVariadic = isVariadic
            self.isInout = isInout
        }

        /// Short label for selector-style display (e.g. "id:" or "_:").
        public var selectorLabel: String {
            if let label {
                return "\(label):"
            }
            return "_:"
        }
    }

    /// Parameters of the function.
    public let parameters: [Parameter]

    /// Return type (nil for Void).
    public let returnType: String?

    /// Whether the function is `async`.
    public let isAsync: Bool

    /// Whether the function `throws`.
    public let isThrowing: Bool

    /// Whether the function `rethrows`.
    public let isRethrowing: Bool

    public init(
        parameters: [Parameter] = [],
        returnType: String? = nil,
        isAsync: Bool = false,
        isThrowing: Bool = false,
        isRethrowing: Bool = false
    ) {
        self.parameters = parameters
        self.returnType = returnType
        self.isAsync = isAsync
        self.isThrowing = isThrowing
        self.isRethrowing = isRethrowing
    }

    /// Selector-style representation (e.g. "(id:)" for `fetch(id:)`).
    public var selectorString: String {
        if parameters.isEmpty {
            return "()"
        }
        return "(" + parameters.map(\.selectorLabel).joined() + ")"
    }
}

// MARK: - Declaration

/// A declaration in Swift source code, as collected by `DeclarationCollector`.
public struct Declaration: Sendable, Hashable, Codable {
    /// The declared name.
    public let name: String

    /// Kind of declaration.
    public let kind: DeclarationKind

    /// Declared access level (see `AccessResolver` for the effective level).
    public let accessLevel: AccessLevel

    /// Applied modifiers.
    public let modifiers: DeclarationModifiers

    /// Location in source (after leading trivia, i.e. the declaration itself, at its first attribute or modifier).
    public let location: SymbolLocation

    /// Location of the declared name: `Model` in `@MainActor final class Model`; the keyword of an `init`, `deinit` or
    /// `subscript`; the extended type of an extension; the path of an import.
    public let nameLocation: SymbolLocation

    /// Range of the entire declaration.
    public let range: SymbolRange

    /// Scope containing this declaration.
    public let scope: ScopeID

    /// Type annotation (if present).
    public let typeAnnotation: String?

    /// Generic parameters (if any).
    public let genericParameters: [String]

    /// Function/method signature (for functions, methods, initializers).
    public let signature: FunctionSignature?

    /// Documentation comment (if any).
    public let documentation: String?

    /// Property wrappers applied to this declaration (for variables/constants).
    public let propertyWrappers: [PropertyWrapperInfo]

    /// SwiftUI type information (for struct/class declarations).
    public let swiftUIInfo: SwiftUITypeInfo?

    /// Protocol conformances declared on this type. For enum cases this
    /// carries the *parent enum's* inheritance list so externally-constructed
    /// cases (raw values, Codable, CaseIterable) can be recognized as roots.
    public let conformances: [String]

    /// Attributes applied to this declaration (e.g. main, objc, IBAction).
    public let attributes: [String]

    public init(
        name: String,
        kind: DeclarationKind,
        accessLevel: AccessLevel = .internal,
        modifiers: DeclarationModifiers = [],
        location: SymbolLocation,
        nameLocation: SymbolLocation? = nil,
        range: SymbolRange,
        scope: ScopeID,
        typeAnnotation: String? = nil,
        genericParameters: [String] = [],
        signature: FunctionSignature? = nil,
        documentation: String? = nil,
        propertyWrappers: [PropertyWrapperInfo] = [],
        swiftUIInfo: SwiftUITypeInfo? = nil,
        conformances: [String] = [],
        attributes: [String] = []
    ) {
        self.name = name
        self.kind = kind
        self.accessLevel = accessLevel
        self.modifiers = modifiers
        self.location = location
        self.nameLocation = nameLocation ?? location
        self.range = range
        self.scope = scope
        self.typeAnnotation = typeAnnotation
        self.genericParameters = genericParameters
        self.signature = signature
        self.documentation = documentation
        self.propertyWrappers = propertyWrappers
        self.swiftUIInfo = swiftUIInfo
        self.conformances = conformances
        self.attributes = attributes
    }
}

// MARK: - Declaration SwiftUI helpers

extension Declaration {
    /// Whether this declaration's property wrappers imply usage
    /// (synthesized accessors the reference collector cannot see).
    public var hasImplicitUsageWrapper: Bool {
        propertyWrappers.contains { $0.kind.impliesUsage }
    }

    /// Whether this is a SwiftUI View type.
    public var isSwiftUIView: Bool {
        swiftUIInfo?.isView ?? false
    }

    /// Whether this is a SwiftUI App entry point.
    public var isSwiftUIApp: Bool {
        swiftUIInfo?.isApp ?? false
    }

    /// Whether this is a SwiftUI preview provider.
    public var isSwiftUIPreview: Bool {
        swiftUIInfo?.isPreview ?? false
    }
}
