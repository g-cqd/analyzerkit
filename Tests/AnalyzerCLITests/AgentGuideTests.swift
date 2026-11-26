import AnalyzerCLI
import Testing

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

@Suite struct AgentGuideTests {
    private func scratch() throws -> String {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("agent-guide-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    private func read(_ path: String) throws -> String {
        String(decoding: try Data(contentsOf: URL(fileURLWithPath: path)), as: UTF8.self)
    }

    private let guide = AgentGuide(
        tool: "litmus",
        skill: "---\nname: litmus\ndescription: d\n---\n# Litmus\n",
        pointer: "Use `litmus agent-guide` for mutation testing."
    )

    @Test func `installing writes each skill and a marked AGENTS.md section, and a second install changes nothing`()
        throws
    {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try Data("# Project\n\nOwn text.\n".utf8).write(to: URL(fileURLWithPath: root + "/AGENTS.md"))
        let first = try guide.install(root: root, targets: [.agents, .claude, .agentsMD])
        #expect(first.map(\.changed) == [true, true, true])
        #expect(try read(root + "/.agents/skills/litmus/SKILL.md") == guide.skill)
        #expect(try read(root + "/.claude/skills/litmus/SKILL.md") == guide.skill)
        let agents = try read(root + "/AGENTS.md")
        #expect(agents.hasPrefix("# Project\n\nOwn text.\n"))
        #expect(agents.contains("<!-- litmus:agent-guide -->\nUse `litmus agent-guide` for mutation testing.\n"))
        #expect(agents.hasSuffix("<!-- /litmus:agent-guide -->\n"))
        let second = try guide.install(root: root, targets: [.agents, .claude, .agentsMD])
        #expect(second.map(\.changed) == [false, false, false])
        #expect(try read(root + "/AGENTS.md") == agents)
    }

    @Test func `a changed pointer replaces its section in place and keeps the rest of AGENTS.md`() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        _ = try guide.install(root: root, targets: [.agentsMD])
        try Data((try read(root + "/AGENTS.md") + "\n## After\n").utf8)
            .write(to: URL(fileURLWithPath: root + "/AGENTS.md"))
        let updated = AgentGuide(tool: "litmus", skill: guide.skill, pointer: "New pointer.")
        #expect(try updated.install(root: root, targets: [.agentsMD]).first?.changed == true)
        let text = try read(root + "/AGENTS.md")
        #expect(text.contains("<!-- litmus:agent-guide -->\nNew pointer.\n<!-- /litmus:agent-guide -->"))
        #expect(!text.contains("Use `litmus agent-guide`"))
        #expect(text.hasSuffix("\n## After\n"))
    }

    @Test func `a symbolic link on the way is refused rather than followed`() throws {
        let root = try scratch()
        let outside = try scratch()
        defer {
            try? FileManager.default.removeItem(atPath: root)
            try? FileManager.default.removeItem(atPath: outside)
        }
        try FileManager.default.createSymbolicLink(atPath: root + "/.claude", withDestinationPath: outside)
        #expect(throws: AgentGuide.Failure.self) { try guide.install(root: root, targets: [.claude]) }
        #expect(!FileManager.default.fileExists(atPath: outside + "/skills/litmus/SKILL.md"))
    }

    @Test(arguments: ["", "../x", "a/b", "UPPER", "with space"])
    func `a tool name that is not a plain lowercase word is refused`(tool: String) throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        #expect(throws: AgentGuide.Failure.self) {
            try AgentGuide(tool: tool, skill: "s", pointer: "p").install(root: root, targets: [.agents])
        }
    }
}
