public enum DirectiveKind: Sendable, Equatable {
    case acceptThis, acceptNext, accept, regionDisable, regionEnable
}

/// A rule-independent directive model. Encoding remains the consuming tool's wire/cache contract.
public struct Directive<Rule: Hashable & Sendable>: Sendable, Equatable {
    /// Empty means every rule; order and duplicates retained for clients whose wire format uses an array.
    public let rules: [Rule]
    public let kind: DirectiveKind
    public let line: Int
    public let reason: String?
    public init(rules: [Rule], kind: DirectiveKind, line: Int, reason: String?) {
        self.rules = rules
        self.kind = kind
        self.line = line
        self.reason = reason
    }
    public func covers(_ rule: Rule) -> Bool { rules.isEmpty || rules.contains(rule) }
}

public struct SuppressionTable<Rule: Hashable & Sendable>: Sendable {
    public init(directives: [Directive<Rule>]) {}
    public func suppression(for rule: Rule, line: Int) -> String?? { nil }
}
