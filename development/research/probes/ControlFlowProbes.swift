// K1–K3. Copy into analyzerkit/Tests/ControlFlowTests/ (it uses that suite's `graph(_:)` helper, made internal for the probe).
// Expected after the fix: K1 throw exit unreachable; K2 throw exit reachable; fallthrough → line 6; `break outer` → line 6.
import ControlFlow
import Testing

@Suite struct ZZProbeTests {
    private func successors(_ g: ControlFlowGraph, line: Int) -> String {
        g.nodes.filter { $0.line == line && !$0.isDeferred }.map { node in
            "\(node.kind)->"
                + node.successors.map { "\($0.kind):\(g.nodes[$0.target].kind)@\(g.nodes[$0.target].line)" }
                .joined(separator: ",")
        }.joined(separator: " | ")
    }

    private func throwExitReachable(_ g: ControlFlowGraph) -> Bool {
        let reach = g.reachable(from: g.entry)
        return g.nodes.contains { if case .exit(.threw) = $0.kind { reach.contains($0.id) } else { false } }
    }

    @Test func probes() {
        print(
            "K1 catch let error:",
            throwExitReachable(graph("func f() throws {\n do { try g() } catch let error { print(error) }\n}")))
        print(
            "K2 for try await:",
            throwExitReachable(graph("func f() async throws {\n for try await x in s { print(x) }\n}")))
        print(
            "K3 fallthrough:",
            successors(
                graph(
                    "func f() {\n switch x {\n case 1:\n  fallthrough\n case 2:\n  print(6)\n default:\n  print(8)\n }\n print(10)\n}"
                ), line: 4))
        print(
            "K3 break outer:",
            successors(
                graph(
                    "func f() {\n outer: do {\n  if c { break outer }\n  print(4)\n }\n print(6)\n}"), line: 3))
    }
}
