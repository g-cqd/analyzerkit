public import SwiftSyntax

/// The control flow of one function body: a node for each simple statement and each condition, with an edge for
/// every way control can go on, including the edge a `try` takes when it throws and the copy of each enclosing
/// `defer` that a `return`, `throw`, `break` or `continue` runs on its way out.
///
/// The graph is built from syntax alone. It is exact about the statement forms it knows (`if`, `guard`, `switch`,
/// `while`, `for`, `repeat`, `do`/`catch`, `defer`, `return`, `throw`, `break`, `continue`, labels) and treats any
/// other statement as one step. Closures and nested functions are not entered: a `return` inside one leaves the
/// closure, not the function, so each is a step of the function that contains it.
public struct ControlFlowGraph: Sendable {
    /// Why control moves from one node to another.
    public enum EdgeKind: Sendable, Hashable {
        /// The next statement, or the start of a `switch` case.
        case next
        /// The condition held.
        case whenTrue
        /// The condition did not hold.
        case whenFalse
        /// A `try`, or a `throw`, left the statement with an error.
        case thrown
        /// The end of a loop body returning to its head.
        case back
    }

    /// How control leaves the function.
    public enum ExitKind: Sendable, Hashable {
        case returned
        case threw
        /// The end of the body was reached.
        case fellOff
        /// `fatalError`, `preconditionFailure` and the like: control does not leave.
        case terminated
    }

    public enum NodeKind: Sendable, Hashable {
        case entry
        /// One simple statement or declaration.
        case statement
        /// The condition list of an `if`, `guard` or `while`, the subject of a `switch`, or the sequence of a `for`.
        case condition
        /// A point where branches meet and that stands for no source.
        case join
        case exit(ExitKind)
    }

    public struct Edge: Sendable, Hashable {
        public let kind: EdgeKind
        public let target: Int

        public init(kind: EdgeKind, target: Int) {
            self.kind = kind
            self.target = target
        }
    }

    public struct Node: Sendable {
        public let id: Int
        public let kind: NodeKind
        /// 1-based source line; 0 for a node that stands for no source.
        public let line: Int
        /// The statement, declaration or condition the node stands for.
        public let syntax: Syntax?
        /// Whether the node is a copy of a `defer` body made for one way out of its scope.
        public let isDeferred: Bool
        public internal(set) var successors: [Edge]
    }

    public let nodes: [Node]

    /// The node control starts at.
    public var entry: Int { 0 }

    /// The exit nodes, one per ``ExitKind`` that the body can reach.
    public var exits: [Int] { nodes.filter { if case .exit = $0.kind { true } else { false } }.map(\.id) }

    init(nodes: [Node]) {
        self.nodes = nodes
    }

    /// The graph of `body`.
    /// - Parameters:
    ///   - body: a function, initializer or accessor body.
    ///   - converter: gives each node its line.
    /// - Complexity: O(*n*) nodes in the number of statements, plus the copies of `defer` bodies: one per exit path
    ///   from each scope that has one.
    public static func build(_ body: CodeBlockSyntax, converter: SourceLocationConverter) -> ControlFlowGraph {
        build(statements: body.statements, converter: converter)
    }

    /// The graph of a list of statements, for a body that has no braces of its own: the implicit getter of a
    /// computed property.
    public static func build(statements: CodeBlockItemListSyntax, converter: SourceLocationConverter)
        -> ControlFlowGraph
    {
        var builder = ControlFlowBuilder(converter: converter)
        return builder.build(statements)
    }

    // MARK: - Queries

    /// The nodes control can reach from `start` along edges `follow` accepts, `start` included.
    public func reachable(from start: Int, following follow: (Node, Edge) -> Bool = { _, _ in true }) -> Set<Int> {
        var seen: Set<Int> = [start]
        var work = [start]
        while let current = work.popLast() {
            for edge in nodes[current].successors
            where follow(nodes[current], edge) && seen.insert(edge.target).inserted {
                work.append(edge.target)
            }
        }
        return seen
    }

    /// A shortest path of node ids from `start` to `goal` through nodes `allowing` accepts, or nil.
    /// - Complexity: O(*n* + *e*).
    public func path(from start: Int, to goal: Int, allowing: (Int) -> Bool = { _ in true }) -> [Int]? {
        var parent: [Int: Int] = [start: start]
        var queue = [start]
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            if current == goal {
                var path = [goal]
                while let previous = parent[path[path.count - 1]], previous != path[path.count - 1] {
                    path.append(previous)
                }
                return path.reversed()
            }
            for edge in nodes[current].successors
            where parent[edge.target] == nil && (edge.target == goal || allowing(edge.target)) {
                parent[edge.target] = current
                queue.append(edge.target)
            }
        }
        return nil
    }

    /// A forward dataflow: the state at the entry of each node, as the least fixed point of `transfer` and `join`.
    ///
    /// `transfer` runs once per edge, with the state at the node's entry, so a condition can say something different
    /// on its true and false edges. Nodes control cannot reach have no state. `State` must have finite height for
    /// the iteration to end; a sanity bound stops it at 64 visits per node and reports what it has.
    /// - Complexity: O(*e* · *h*) for a lattice of height *h*.
    public func solve<State: Equatable>(
        initial: State,
        join: (State, State) -> State,
        transfer: (Node, Edge, State) -> State
    ) -> [State?] {
        var entryStates = [State?](repeating: nil, count: nodes.count)
        var visits = [Int](repeating: 0, count: nodes.count)
        entryStates[entry] = initial
        var work = [entry]
        while let current = work.popLast() {
            visits[current] += 1
            guard visits[current] <= 64, let state = entryStates[current] else { continue }
            for edge in nodes[current].successors {
                let out = transfer(nodes[current], edge, state)
                let merged = entryStates[edge.target].map { join($0, out) } ?? out
                if entryStates[edge.target] != merged {
                    entryStates[edge.target] = merged
                    work.append(edge.target)
                }
            }
        }
        return entryStates
    }
}
