import ControlFlow
import SwiftParser
import SwiftSyntax
import Testing

/// The graph of the first function in `source`, with the lines of its body counted from 1 at the `func` line.
private func graph(_ source: String) -> ControlFlowGraph {
    let tree = Parser.parse(source: source)
    let converter = SourceLocationConverter(fileName: "T.swift", tree: tree)
    final class First: SyntaxVisitor {
        var body: CodeBlockSyntax?
        init() { super.init(viewMode: .sourceAccurate) }
        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
            if body == nil { body = node.body }
            return .skipChildren
        }
    }
    let finder = First()
    finder.walk(tree)
    return ControlFlowGraph.build(finder.body ?? CodeBlockSyntax(statements: []), converter: converter)
}

extension ControlFlowGraph {
    func exit(_ kind: ExitKind) -> Int? {
        nodes.first { if case .exit(let found) = $0.kind { found == kind } else { false } }?.id
    }

    /// The lines of the statement nodes control can reach from the entry before it reaches `kind`.
    func reaches(_ kind: ExitKind) -> Bool { exit(kind).map { reachable(from: entry).contains($0) } ?? false }

    /// The lines on a shortest path from the entry to `kind`.
    func lines(to kind: ExitKind) -> [Int] {
        guard let goal = exit(kind), let route = path(from: entry, to: goal) else { return [] }
        return route.map { nodes[$0].line }.filter { $0 > 0 }
    }
}

@Suite struct ControlFlowTests {
    @Test func `a straight body runs its statements in order and falls off the end`() {
        let g = graph("func f() {\n let a = 1\n let b = 2\n}")
        #expect(g.lines(to: .fellOff) == [2, 3])
        #expect(g.reaches(.fellOff) && !g.reaches(.returned) && !g.reaches(.threw))
    }

    @Test func `an if with no else can be skipped and an if with an else cannot`() {
        let skip = graph("func f(_ c: Bool) {\n if c {\n  a()\n }\n b()\n}")
        #expect(skip.lines(to: .fellOff) == [2, 5])
        let both = graph("func f(_ c: Bool) {\n if c {\n  a()\n } else {\n  b()\n }\n}")
        #expect(both.lines(to: .fellOff).count == 2)
    }

    @Test func `a guard whose body returns leaves a true edge to the rest`() {
        let g = graph("func f(_ c: Bool) {\n guard c else {\n  return\n }\n work()\n}")
        #expect(g.lines(to: .returned) == [2, 3])
        #expect(g.lines(to: .fellOff) == [2, 5])
    }

    @Test func `a try can throw to the exit and a try question mark cannot`() {
        #expect(graph("func f() throws {\n try a()\n}").reaches(.threw))
        #expect(!graph("func f() {\n _ = try? a()\n}").reaches(.threw))
        #expect(!graph("func f() {\n _ = try! a()\n}").reaches(.threw))
        #expect(!graph("func f() throws {\n let g = { try a() }\n}").reaches(.threw), "a closure is not entered")
    }

    @Test func `a throw statement leaves by the throw exit only`() {
        let g = graph("func f() throws {\n throw E()\n}")
        #expect(g.reaches(.threw) && !g.reaches(.fellOff))
    }

    @Test func `a defer runs on the normal end, on a return and on a throw`() {
        let g = graph("func f(_ c: Bool) throws {\n defer { cleanup() }\n if c { return }\n try a()\n}")
        for kind in [ControlFlowGraph.ExitKind.returned, .threw, .fellOff] {
            let route = g.path(from: g.entry, to: g.exit(kind)!)!
            #expect(route.contains { g.nodes[$0].isDeferred }, "no cleanup before \(kind)")
        }
    }

    @Test func `a defer registered after a return does not run for it`() {
        let g = graph("func f(_ c: Bool) {\n if c { return }\n defer { cleanup() }\n work()\n}")
        let route = g.path(from: g.entry, to: g.exit(.returned)!)!
        #expect(!route.contains { g.nodes[$0].isDeferred })
    }

    @Test func `defers run last first`() {
        let g = graph("func f() {\n defer { one() }\n defer { two() }\n}")
        let route = g.path(from: g.entry, to: g.exit(.fellOff)!)!
        #expect(route.filter { g.nodes[$0].isDeferred }.map { g.nodes[$0].line } == [3, 2])
    }

    @Test func `a do with a catch-all stops a throw and one without passes it on`() {
        let caught = graph("func f() throws {\n do {\n  try a()\n } catch {\n  recover()\n }\n}")
        #expect(!caught.reaches(.threw) && caught.reaches(.fellOff))
        let partial = graph("func f() throws {\n do {\n  try a()\n } catch let e as E {\n  recover()\n }\n}")
        #expect(partial.reaches(.threw))
    }

    @Test func `a throw inside a catch body leaves the function`() {
        let g = graph("func f() throws {\n do {\n  try a()\n } catch {\n  throw E()\n }\n}")
        #expect(g.reaches(.threw))
    }

    @Test func `a loop returns to its head, break leaves it and continue repeats it`() {
        let g = graph("func f() {\n while c() {\n  if d() { break }\n  if e() { continue }\n  work()\n }\n done()\n}")
        let head = g.nodes.first { $0.kind == .condition && $0.line == 2 }!
        #expect(g.nodes.contains { $0.successors.contains { $0.kind == .back && $0.target == head.id } })
        #expect(g.lines(to: .fellOff) == [2, 7])
        #expect(
            g.path(
                from: g.entry, to: g.nodes.first { $0.line == 7 }!.id,
                allowing: { g.nodes[$0].line != 2 || $0 == head.id }) != nil)
    }

    @Test func `break in a switch leaves the switch and not the loop around it`() {
        let g = graph(
            "func f() {\n for x in xs {\n  switch x {\n  case 1:\n   break\n  default:\n   other()\n  }\n  after()\n }\n}"
        )
        let after = g.nodes.first { $0.line == 9 }!
        let breakNode = g.nodes.first { $0.line == 5 }!
        #expect(g.reachable(from: breakNode.id).contains(after.id))
    }

    @Test func `fatalError ends control without leaving by any exit`() {
        let g = graph("func f() {\n fatalError(\"no\")\n}")
        #expect(g.reaches(.terminated) && !g.reaches(.fellOff) && !g.reaches(.returned))
    }

    @Test func `code after a return is not in the graph`() {
        let g = graph("func f() {\n return\n unreachable()\n}")
        #expect(!g.nodes.contains { $0.line == 3 })
    }

    @Test func `a labelled break leaves the outer loop`() {
        let g = graph(
            "func f() {\n outer: for a in xs {\n  for b in ys {\n   break outer\n  }\n  inner()\n }\n done()\n}")
        let breakNode = g.nodes.first { $0.line == 4 }!
        let inner = g.nodes.first { $0.line == 6 }!
        let done = g.nodes.first { $0.line == 8 }!
        let after = g.reachable(from: breakNode.id)
        #expect(after.contains(done.id) && !after.contains(inner.id))
    }

    @Test func `a repeat loop runs its body before testing`() {
        let g = graph("func f() {\n repeat {\n  work()\n } while c()\n}")
        #expect(g.lines(to: .fellOff) == [3, 4])
    }

    @Test func `the dataflow solver finds what holds at each node and refines on the edges`() {
        let g = graph("func f(_ c: Bool) {\n let x = open()\n if c {\n  close(x)\n }\n}")
        // State: whether `x` is still open. Opened at line 2, closed at line 4.
        let states: [Bool?] = g.solve(
            initial: false, join: { $0 || $1 },
            transfer: { node, _, state in
                switch node.line {
                case 2: true
                case 4: false
                default: state
                }
            })
        let exit = g.exit(.fellOff)!
        #expect(states[exit] == true, "the path that skips the close leaves it open")
    }

    @Test func `a body nested past the limit does not overflow the stack`() {
        let depth = 1_000
        let source =
            "func f() {\n" + String(repeating: "if c {\n", count: depth) + "work()\n"
            + String(repeating: "}\n", count: depth) + "}"
        #expect(graph(source).nodes.count > 1, "deeply nested source is bounded, not a stack overflow")
    }
}
