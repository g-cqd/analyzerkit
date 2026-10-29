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

/// A stable line-order sweep. Regions are state switches, not nested stacks; line directives win over regions.
public struct SuppressionTable<Rule: Hashable & Sendable>: Sendable {
    private let directives: [Directive<Rule>]
    public init(directives: [Directive<Rule>]) {
        self.directives = directives.sorted { $0.line < $1.line }
    }
    /// nil: not suppressed; .some(nil): suppressed without a reason; .some(reason): suppressed with a reason.
    public func suppression(for rule: Rule, line: Int) -> String?? {
        var disabled = false
        var reason: String?
        for directive in directives where directive.covers(rule) {
            switch directive.kind {
            case .acceptThis where directive.line == line: return .some(directive.reason)
            case .acceptNext where directive.line == line - 1: return .some(directive.reason)
            case .accept where directive.line == line || directive.line == line - 1: return .some(directive.reason)
            case .regionDisable where directive.line <= line:
                disabled = true
                reason = directive.reason
            case .regionEnable where directive.line <= line:
                disabled = false
                reason = nil
            default: break
            }
        }
        return disabled ? .some(reason) : nil
    }
}
