#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

/// A tool's guide for coding agents (`<tool> agent-guide --install`): a skill file each agent harness reads, and a
/// pointer in the repository's `AGENTS.md`, written idempotently so installing twice changes nothing.
///
/// The skill goes to `.agents/skills/<tool>/SKILL.md` and `.claude/skills/<tool>/SKILL.md`. The pointer is a section
/// between `<!-- <tool>:agent-guide -->` and `<!-- /<tool>:agent-guide -->`, replaced in place when present, appended
/// otherwise; the rest of `AGENTS.md` is kept byte for byte. Nothing is written through a symbolic link.
public struct AgentGuide: Sendable, Equatable {
    /// Where a guide goes.
    public enum Target: String, CaseIterable, Sendable {
        /// `.agents/skills/<tool>/SKILL.md`.
        case agents
        /// `.claude/skills/<tool>/SKILL.md`.
        case claude
        /// The marked section of `AGENTS.md`.
        case agentsMD = "agents-md"
    }

    /// Why nothing was written: the path (or tool name) refused, and the reason.
    public struct Failure: Error, Sendable, Equatable, CustomStringConvertible {
        public let subject: String
        public let reason: String
        public var description: String { "\(subject): \(reason)" }

        static func invalidToolName(_ name: String) -> Self { Self(subject: name, reason: "not a lowercase word") }
        static func symbolicLink(_ path: String) -> Self {
            Self(subject: path, reason: "a symbolic link, not followed")
        }
        static func notARegularFile(_ path: String) -> Self { Self(subject: path, reason: "not a regular file") }
        static func unbalancedMarkers(_ path: String) -> Self {
            Self(subject: path, reason: "an agent-guide start marker without its end, or the reverse")
        }
    }

    /// One file the installation wrote or found up to date.
    public struct Installation: Sendable, Equatable {
        public let path: String
        /// False when the file already held what would be written.
        public let changed: Bool
    }

    public let tool: String
    /// The skill file's whole content, front matter included.
    public let skill: String
    /// The text of the `AGENTS.md` section.
    public let pointer: String

    public init(tool: String, skill: String, pointer: String) {
        self.tool = tool
        self.skill = skill
        self.pointer = pointer
    }

    /// Writes the guide under `root` for each of `targets`, in order.
    /// - Throws: ``Failure``, or the file system's error; files written before a failure stay written.
    public func install(root: String, targets: [Target]) throws -> [Installation] {
        guard !tool.isEmpty, tool.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" })
        else { throw Failure.invalidToolName(tool) }
        var installations: [Installation] = []
        for target in targets {
            switch target {
            case .agents:
                installations.append(try write(skill, at: [".agents", "skills", tool, "SKILL.md"], root: root))
            case .claude:
                installations.append(try write(skill, at: [".claude", "skills", tool, "SKILL.md"], root: root))
            case .agentsMD:
                let path = root + "/AGENTS.md"
                let current = try existing(path)
                installations.append(
                    try write(try section(in: current ?? "", path: path), at: ["AGENTS.md"], root: root)
                )
            }
        }
        return installations
    }

    /// `text` with the tool's marked section holding ``pointer``: replaced where it is, appended when absent.
    private func section(in text: String, path: String) throws -> String {
        let start = "<!-- \(tool):agent-guide -->"
        let end = "<!-- /\(tool):agent-guide -->"
        let trimmed = pointer.drop { $0.isNewline }.reversed().drop { $0.isNewline }.reversed()
        let block = start + "\n" + String(trimmed) + "\n" + end
        // The standard library's search, not Foundation's: FoundationEssentials on Linux has neither.
        let opening = text.firstRange(of: start)
        let closing = text.firstRange(of: end)
        switch (opening, closing) {
        case (let opening?, let closing?) where opening.upperBound <= closing.lowerBound:
            var replaced = text
            replaced.replaceSubrange(opening.lowerBound..<closing.upperBound, with: block)
            return replaced
        case (nil, nil):
            let separator = text.isEmpty ? "" : text.hasSuffix("\n\n") ? "" : text.hasSuffix("\n") ? "\n" : "\n\n"
            return text + separator + block + "\n"
        default:
            throw Failure.unbalancedMarkers(path)
        }
    }

    /// The text of the regular file at `path`, nil when there is none; a link is refused.
    private func existing(_ path: String) throws -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        let type = attributes[.type] as? FileAttributeType
        if type == .typeSymbolicLink { throw Failure.symbolicLink(path) }
        guard type == .typeRegular else { throw Failure.notARegularFile(path) }
        return String(decoding: try Data(contentsOf: URL(fileURLWithPath: path)), as: UTF8.self)
    }

    /// Writes `text` at `components` under `root`, creating directories, unless the file already holds it.
    private func write(_ text: String, at components: [String], root: String) throws -> Installation {
        var directory = root
        for component in components.dropLast() {
            directory += "/" + component
            let attributes = try? FileManager.default.attributesOfItem(atPath: directory)
            switch attributes?[.type] as? FileAttributeType {
            case nil: try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false)
            case .typeDirectory?: break
            case .typeSymbolicLink?: throw Failure.symbolicLink(directory)
            default: throw Failure.notARegularFile(directory)
            }
        }
        let path = directory + "/" + (components.last ?? "")
        if try existing(path) == text { return Installation(path: path, changed: false) }
        try Data(text.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
        return Installation(path: path, changed: true)
    }
}
