import SwiftSyntax

/// Lowers a function body to a ``ControlFlowGraph``.
///
/// Statements are lowered in order, each taking the edges still waiting for a target (`Open`) and returning the
/// ones it leaves open. A statement that never completes (`return`, `throw`, `fatalError`) returns none, so what
/// follows it in the block is dead and gets no node. Leaving a scope by any route but its end runs the `defer`
/// bodies registered so far in each scope left, last first, as copies of those bodies on that route.
struct ControlFlowBuilder {
    private typealias Kind = ControlFlowGraph.EdgeKind

    /// An edge whose target is not yet known.
    private struct Open {
        var node: Int
        var kind: Kind
    }

    private struct Scope {
        var defers: [CodeBlockSyntax] = []
    }

    /// A loop or `switch`, which `break` leaves and, for a loop, `continue` repeats.
    private struct Frame {
        var label: String?
        var isLoop: Bool
        var continueTarget: Int?
        var scopeDepth: Int
        var breaks: [Open] = []
    }

    private struct CatchFrame {
        var entry: Int
        var scopeDepth: Int
    }

    /// Statement nesting beyond this is one step: hostile input must not overflow the stack.
    private static let maximumDepth = 200

    private let converter: SourceLocationConverter
    private var nodes: [ControlFlowGraph.Node] = []
    private var exitIDs: [ControlFlowGraph.ExitKind: Int] = [:]
    private var scopes: [Scope] = []
    private var frames: [Frame] = []
    private var catches: [CatchFrame] = []
    private var deferring = 0
    private var depth = 0
    private var pendingLabel: String?

    init(converter: SourceLocationConverter) {
        self.converter = converter
    }

    mutating func build(_ body: CodeBlockSyntax) -> ControlFlowGraph {
        let entry = makeNode(.entry, syntax: nil, line: 0)
        let remaining = block(body.statements, after: [Open(node: entry, kind: .next)])
        connect(remaining, to: exit(.fellOff))
        return ControlFlowGraph(nodes: nodes)
    }

    // MARK: - Nodes and edges

    private mutating func makeNode(_ kind: ControlFlowGraph.NodeKind, syntax: Syntax?, line: Int) -> Int {
        nodes.append(
            ControlFlowGraph.Node(
                id: nodes.count, kind: kind, line: line, syntax: syntax, isDeferred: deferring > 0, successors: []))
        return nodes.count - 1
    }

    private func line(of syntax: some SyntaxProtocol) -> Int {
        converter.location(for: syntax.positionAfterSkippingLeadingTrivia).line
    }

    private mutating func exit(_ kind: ControlFlowGraph.ExitKind) -> Int {
        if let existing = exitIDs[kind] { return existing }
        let id = makeNode(.exit(kind), syntax: nil, line: 0)
        exitIDs[kind] = id
        return id
    }

    private mutating func connect(_ opens: [Open], to target: Int, as kind: Kind? = nil) {
        for open in opens {
            let edge = ControlFlowGraph.Edge(kind: kind ?? open.kind, target: target)
            if !nodes[open.node].successors.contains(edge) { nodes[open.node].successors.append(edge) }
        }
    }

    private mutating func step(_ kind: ControlFlowGraph.NodeKind, _ syntax: some SyntaxProtocol, after opens: [Open])
        -> Int
    {
        let id = makeNode(kind, syntax: Syntax(syntax), line: line(of: syntax))
        connect(opens, to: id)
        return id
    }

    // MARK: - Leaving scopes

    /// Runs the `defer`s of every scope from the innermost down to index `scopeDepth`, then reaches `target`.
    private mutating func escape(_ opens: [Open], toScopeDepth scopeDepth: Int, then target: Int) {
        var current = opens
        var index = scopes.count - 1
        while index >= scopeDepth, !current.isEmpty {
            for body in scopes[index].defers.reversed() { current = lowerDefer(body, after: current) }
            index -= 1
        }
        connect(current, to: target)
    }

    private mutating func lowerDefer(_ body: CodeBlockSyntax, after opens: [Open]) -> [Open] {
        deferring += 1
        defer { deferring -= 1 }
        // A `defer` body cannot leave its scope, so its own scope stack is the one it runs in.
        let saved = scopes
        scopes.append(Scope())
        let remaining = lowerItems(body.statements, after: opens)
        scopes = saved
        return remaining
    }

    private mutating func throwTarget() -> (node: Int, scopeDepth: Int) {
        if let frame = catches.last { return (frame.entry, frame.scopeDepth) }
        return (exit(.threw), 0)
    }

    private mutating func addThrowEdge(from node: Int) {
        let target = throwTarget()
        escape([Open(node: node, kind: .thrown)], toScopeDepth: target.scopeDepth, then: target.node)
    }

    // MARK: - Statements

    private mutating func block(_ statements: CodeBlockItemListSyntax, after opens: [Open]) -> [Open] {
        scopes.append(Scope())
        var remaining = lowerItems(statements, after: opens)
        if !remaining.isEmpty, let scope = scopes.last {
            for body in scope.defers.reversed() { remaining = lowerDefer(body, after: remaining) }
        }
        scopes.removeLast()
        return remaining
    }

    private mutating func lowerItems(_ statements: CodeBlockItemListSyntax, after opens: [Open]) -> [Open] {
        var current = opens
        for item in statements {
            if current.isEmpty { break }
            current = lower(item, after: current)
        }
        return current
    }

    private mutating func lower(_ item: CodeBlockItemSyntax, after opens: [Open]) -> [Open] {
        depth += 1
        defer { depth -= 1 }
        if depth > Self.maximumDepth { return simple(item.item, after: opens) }
        switch item.item {
        case .decl(let declaration):
            return simple(declaration, after: opens)
        case .expr(let expression):
            return lowerExpression(expression, after: opens)
        case .stmt(let statement):
            return lowerStatement(statement, after: opens)
        }
    }

    private mutating func lowerExpression(_ expression: ExprSyntax, after opens: [Open]) -> [Open] {
        if let conditional = expression.as(IfExprSyntax.self) { return lowerIf(conditional, after: opens) }
        if let switched = expression.as(SwitchExprSyntax.self) { return lowerSwitch(switched, after: opens) }
        if Self.isTerminal(expression) {
            let id = step(.statement, expression, after: opens)
            connect([Open(node: id, kind: .next)], to: exit(.terminated))
            return []
        }
        return simple(expression, after: opens)
    }

    private mutating func lowerStatement(_ statement: StmtSyntax, after opens: [Open]) -> [Open] {
        // `if` and `switch` at statement level are expressions wrapped as statements.
        if let wrapper = statement.as(ExpressionStmtSyntax.self) {
            return lowerExpression(wrapper.expression, after: opens)
        }
        if let node = statement.as(GuardStmtSyntax.self) { return lowerGuard(node, after: opens) }
        if let node = statement.as(WhileStmtSyntax.self) {
            return lowerLoop(
                head: node.conditions, body: node.body, after: opens, repeats: false)
        }
        if let node = statement.as(ForStmtSyntax.self) {
            return lowerLoop(head: node.sequence, body: node.body, after: opens, repeats: false)
        }
        if let node = statement.as(RepeatStmtSyntax.self) { return lowerRepeat(node, after: opens) }
        if let node = statement.as(DoStmtSyntax.self) { return lowerDo(node, after: opens) }
        if let node = statement.as(DeferStmtSyntax.self) {
            scopes[scopes.count - 1].defers.append(node.body)
            return opens
        }
        if let node = statement.as(LabeledStmtSyntax.self) {
            pendingLabel = node.label.text
            defer { pendingLabel = nil }
            return lowerStatement(node.statement, after: opens)
        }
        if let node = statement.as(ReturnStmtSyntax.self) {
            let id = step(.statement, node, after: opens)
            if node.expression.map(Self.canThrow) == true { addThrowEdge(from: id) }
            escape([Open(node: id, kind: .next)], toScopeDepth: 0, then: exit(.returned))
            return []
        }
        if let node = statement.as(ThrowStmtSyntax.self) {
            let id = step(.statement, node, after: opens)
            addThrowEdge(from: id)
            return []
        }
        if let node = statement.as(BreakStmtSyntax.self) { return lowerBreak(node, after: opens) }
        if let node = statement.as(ContinueStmtSyntax.self) { return lowerContinue(node, after: opens) }
        return simple(statement, after: opens)
    }

    private mutating func simple(_ syntax: some SyntaxProtocol, after opens: [Open]) -> [Open] {
        let id = step(.statement, syntax, after: opens)
        if Self.canThrow(syntax) { addThrowEdge(from: id) }
        return [Open(node: id, kind: .next)]
    }

    private mutating func lowerIf(_ node: IfExprSyntax, after opens: [Open]) -> [Open] {
        let condition = step(.condition, node.conditions, after: opens)
        if Self.canThrow(node.conditions) { addThrowEdge(from: condition) }
        let taken = block(node.body.statements, after: [Open(node: condition, kind: .whenTrue)])
        let notTaken = [Open(node: condition, kind: .whenFalse)]
        switch node.elseBody {
        case .codeBlock(let other): return taken + block(other.statements, after: notTaken)
        case .ifExpr(let chained): return taken + lowerIf(chained, after: notTaken)
        case nil: return taken + notTaken
        }
    }

    private mutating func lowerGuard(_ node: GuardStmtSyntax, after opens: [Open]) -> [Open] {
        let condition = step(.condition, node.conditions, after: opens)
        if Self.canThrow(node.conditions) { addThrowEdge(from: condition) }
        // The body of a guard leaves the scope; if it somehow does not, its end falls through.
        let leftover = block(node.body.statements, after: [Open(node: condition, kind: .whenFalse)])
        return [Open(node: condition, kind: .whenTrue)] + leftover
    }

    private mutating func lowerLoop(
        head: some SyntaxProtocol, body: CodeBlockSyntax, after opens: [Open], repeats: Bool
    ) -> [Open] {
        let label = pendingLabel
        pendingLabel = nil
        let header = step(.condition, head, after: opens)
        if Self.canThrow(head) { addThrowEdge(from: header) }
        frames.append(Frame(label: label, isLoop: true, continueTarget: header, scopeDepth: scopes.count))
        let end = block(body.statements, after: [Open(node: header, kind: .whenTrue)])
        connect(end, to: header, as: .back)
        let frame = frames.removeLast()
        return [Open(node: header, kind: .whenFalse)] + frame.breaks
    }

    private mutating func lowerRepeat(_ node: RepeatStmtSyntax, after opens: [Open]) -> [Open] {
        let label = pendingLabel
        pendingLabel = nil
        let top = makeNode(.join, syntax: nil, line: 0)
        connect(opens, to: top)
        let condition = makeNode(.condition, syntax: Syntax(node.condition), line: line(of: node.condition))
        frames.append(Frame(label: label, isLoop: true, continueTarget: condition, scopeDepth: scopes.count))
        let end = block(node.body.statements, after: [Open(node: top, kind: .next)])
        connect(end, to: condition)
        if Self.canThrow(node.condition) { addThrowEdge(from: condition) }
        connect([Open(node: condition, kind: .whenTrue)], to: top, as: .back)
        let frame = frames.removeLast()
        return [Open(node: condition, kind: .whenFalse)] + frame.breaks
    }

    private mutating func lowerSwitch(_ node: SwitchExprSyntax, after opens: [Open]) -> [Open] {
        let label = pendingLabel
        pendingLabel = nil
        let subject = step(.condition, node.subject, after: opens)
        if Self.canThrow(node.subject) { addThrowEdge(from: subject) }
        frames.append(Frame(label: label, isLoop: false, continueTarget: nil, scopeDepth: scopes.count))
        var results: [Open] = []
        var hasCase = false
        for element in node.cases {
            guard case .switchCase(let switchCase) = element else { continue }
            hasCase = true
            results += block(switchCase.statements, after: [Open(node: subject, kind: .next)])
        }
        let frame = frames.removeLast()
        return (hasCase ? results : [Open(node: subject, kind: .next)]) + frame.breaks
    }

    private mutating func lowerDo(_ node: DoStmtSyntax, after opens: [Open]) -> [Open] {
        guard !node.catchClauses.isEmpty else { return block(node.body.statements, after: opens) }
        let entry = makeNode(.join, syntax: nil, line: 0)
        catches.append(CatchFrame(entry: entry, scopeDepth: scopes.count))
        var results = block(node.body.statements, after: opens)
        catches.removeLast()
        var catchesAll = false
        for clause in node.catchClauses {
            if clause.catchItems.isEmpty { catchesAll = true }
            results += block(clause.body.statements, after: [Open(node: entry, kind: .next)])
        }
        if !catchesAll {
            let outer = throwTarget()
            escape([Open(node: entry, kind: .thrown)], toScopeDepth: outer.scopeDepth, then: outer.node)
        }
        return results
    }

    private mutating func lowerBreak(_ node: BreakStmtSyntax, after opens: [Open]) -> [Open] {
        let id = step(.statement, node, after: opens)
        let wanted = node.label?.text
        guard let index = frames.lastIndex(where: { wanted == nil || $0.label == wanted }) else { return [] }
        // Collect the open edges after the defers of the scopes the break leaves.
        var current = [Open(node: id, kind: .next)]
        var scopeIndex = scopes.count - 1
        while scopeIndex >= frames[index].scopeDepth {
            for body in scopes[scopeIndex].defers.reversed() { current = lowerDefer(body, after: current) }
            scopeIndex -= 1
        }
        frames[index].breaks += current
        return []
    }

    private mutating func lowerContinue(_ node: ContinueStmtSyntax, after opens: [Open]) -> [Open] {
        let id = step(.statement, node, after: opens)
        let wanted = node.label?.text
        guard let frame = frames.last(where: { $0.isLoop && (wanted == nil || $0.label == wanted) }),
            let target = frame.continueTarget
        else { return [] }
        escape([Open(node: id, kind: .next)], toScopeDepth: frame.scopeDepth, then: target)
        return []
    }

    // MARK: - Syntax questions

    private static let terminalCalls: Set<String> = ["fatalError", "preconditionFailure", "exit", "abort"]

    private static func isTerminal(_ expression: ExprSyntax) -> Bool {
        guard let call = expression.as(FunctionCallExprSyntax.self),
            let callee = call.calledExpression.as(DeclReferenceExprSyntax.self)
        else { return false }
        return terminalCalls.contains(callee.baseName.text)
    }

    /// Whether running `syntax` can throw: a `try` that is neither `try?` nor `try!`, outside any closure.
    static func canThrow(_ syntax: some SyntaxProtocol) -> Bool {
        let finder = ThrowingTryFinder()
        finder.walk(syntax)
        return finder.found
    }
}

private final class ThrowingTryFinder: SyntaxVisitor {
    private(set) var found = false

    init() { super.init(viewMode: .sourceAccurate) }

    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        if node.questionOrExclamationMark == nil { found = true }
        return found ? .skipChildren : .visitChildren
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
}
