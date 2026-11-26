#if canImport(FoundationEssentials)
    public import FoundationEssentials
#else
    public import Foundation
#endif

/// Reviewed acceptances, kept out of the source (`.<tool>-accepted.json`): findings a team examined and decided not to
/// act on, each with the reason, so a tool leaves them out of its report without a comment in production code.
///
/// Unlike a ``FindingBaseline``, which records debt wholesale and silently, every entry here is one decision with its
/// justification, and survives edits elsewhere in the file: an entry matches a finding by the tool's stable id first,
/// then by its ``Anchor`` (path, enclosing declaration, rule, whitespace-collapsed text and replacement) when that
/// matches exactly one finding. An entry matching nothing is stale, and the tool says so.
public struct AcceptanceFile: Codable, Sendable, Equatable {
    /// The version this type reads and writes.
    public static let currentVersion = 1
    /// The fewest non-whitespace characters a reason may have: "ok" justifies nothing.
    public static let minimumReasonLength = 10
    /// The largest file read, in bytes.
    public static let byteCap = 4 << 20

    /// Why a file or an entry was refused. A file is refused whole: half an acceptance list would report what the team
    /// accepted, or hide what it did not.
    public enum Failure: Error, Sendable, Equatable, CustomStringConvertible {
        case malformed(String)
        case unsupportedVersion(Int)
        /// The file belongs to another tool.
        case otherTool(String)
        case duplicateID(String)
        case reasonTooShort(id: String)

        public var description: String {
            switch self {
            case .malformed(let detail): "malformed acceptance file: \(detail)"
            case .unsupportedVersion(let version): "unsupported acceptance file version \(version)"
            case .otherTool(let tool): "the acceptance file belongs to \(tool)"
            case .duplicateID(let id): "\(id) is accepted twice"
            case .reasonTooShort(let id):
                "the reason for \(id) needs at least \(minimumReasonLength) non-whitespace characters"
            }
        }
    }

    /// What identifies a finding apart from its id, whitespace-insensitive in its text.
    public struct Anchor: Hashable, Sendable {
        public let path: String
        public let declaration: String
        public let rule: String
        public let text: String
        public let replacement: String?

        public init(path: String, declaration: String, rule: String, text: String, replacement: String? = nil) {
            self.path = path
            self.declaration = declaration
            self.rule = rule
            self.text = Fingerprint.normalized(text)
            self.replacement = replacement.map(Fingerprint.normalized)
        }
    }

    /// One accepted finding.
    public struct Entry: Codable, Sendable, Equatable {
        /// The tool's stable identity of the finding (an anchored fingerprint, a mutant id).
        public let id: String
        /// Relative to the repository or the analyzed root, as the tool reports it.
        public let path: String
        /// The enclosing declaration (`Type.method(_:)`), empty at file scope.
        public let declaration: String
        public let rule: String
        /// The finding's source text.
        public let text: String
        /// What the tool would put instead (a mutant's replacement); nil when it proposes nothing.
        public let replacement: String?
        public let reason: String
        /// When it was accepted, `YYYY-MM-DD`, as the caller's clock says.
        public let addedAt: String

        public init(
            id: String,
            path: String,
            declaration: String,
            rule: String,
            text: String,
            replacement: String?,
            reason: String,
            addedAt: String
        ) {
            self.id = id
            self.path = path
            self.declaration = declaration
            self.rule = rule
            self.text = text
            self.replacement = replacement
            self.reason = reason
            self.addedAt = addedAt
        }

        public var anchor: Anchor {
            Anchor(path: path, declaration: declaration, rule: rule, text: text, replacement: replacement)
        }
    }

    /// What ``match(_:id:anchor:)`` decided.
    public struct Matches<Item> {
        /// The accepted findings with their entries, in input order.
        public let accepted: [(item: Item, entry: Entry)]
        /// The findings no entry accepts, in input order.
        public let remaining: [Item]
        /// The entries that matched no finding, in file order.
        public let stale: [Entry]
    }

    public let schemaVersion: Int
    public let tool: String
    /// Sorted by path, declaration, rule and id.
    public private(set) var accepted: [Entry]

    /// An empty file for `tool`.
    public init(tool: String) {
        schemaVersion = Self.currentVersion
        self.tool = tool
        accepted = []
    }

    /// The file in `data`, written by `tool`, of the current version, every reason long enough, each id once.
    /// - Throws: ``Failure``.
    public static func decode(_ data: Data, tool: String) throws(Failure) -> Self {
        guard data.count <= byteCap else { throw .malformed("larger than \(byteCap) bytes") }
        let file: Self
        do { file = try JSONDecoder().decode(Self.self, from: data) } catch {
            throw .malformed(String(describing: error))
        }
        guard file.schemaVersion == currentVersion else { throw .unsupportedVersion(file.schemaVersion) }
        guard file.tool == tool else { throw .otherTool(file.tool) }
        var seen: Set<String> = []
        for entry in file.accepted {
            guard seen.insert(entry.id).inserted else { throw .duplicateID(entry.id) }
            try validate(reason: entry.reason, id: entry.id)
        }
        var sorted = file
        sorted.accepted = Self.sorted(file.accepted)
        return sorted
    }

    /// The file's bytes: pretty-printed, keys sorted, a final newline; the same set always writes the same bytes.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }

    /// This file with `entry`, replacing the entry of the same id.
    /// - Throws: ``Failure/reasonTooShort(id:)``.
    public func adding(_ entry: Entry) throws(Failure) -> Self {
        try Self.validate(reason: entry.reason, id: entry.id)
        var copy = self
        copy.accepted = Self.sorted(accepted.filter { $0.id != entry.id } + [entry])
        return copy
    }

    /// This file without the entry `id`, and whether it had one.
    public func removing(id: String) -> (file: Self, found: Bool) {
        var copy = self
        copy.accepted.removeAll { $0.id == id }
        return (copy, copy.accepted.count != accepted.count)
    }

    /// Splits `items` into accepted and remaining, and lists the stale entries. An entry accepts the item with its id;
    /// an entry whose id no item has accepts the one item with its anchor, and none when several have it.
    /// - Complexity: O(*n* + *e*) for *n* items and *e* entries.
    public func match<Item>(
        _ items: [Item],
        id: (Item) -> String,
        anchor: (Item) -> Anchor
    ) -> Matches<Item> {
        let ids = items.map(id)
        let present = Set(ids)
        var byAnchor: [Anchor: [Int]] = [:]
        for (index, item) in items.enumerated() { byAnchor[anchor(item), default: []].append(index) }
        var entryOf: [Int: Entry] = [:]
        var stale: [Entry] = []
        let indexOfID = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        // Ids first, so an anchor never takes the finding an id names.
        var byAnchorOnly: [Entry] = []
        for entry in accepted {
            if present.contains(entry.id), let index = indexOfID[entry.id] {
                entryOf[index] = entry
            } else {
                byAnchorOnly.append(entry)
            }
        }
        for entry in byAnchorOnly {
            if let candidates = byAnchor[entry.anchor], candidates.count == 1, entryOf[candidates[0]] == nil {
                entryOf[candidates[0]] = entry
            } else {
                stale.append(entry)
            }
        }
        stale = Self.sorted(stale)
        var acceptedItems: [(item: Item, entry: Entry)] = []
        var remaining: [Item] = []
        for (index, item) in items.enumerated() {
            if let entry = entryOf[index] { acceptedItems.append((item, entry)) } else { remaining.append(item) }
        }
        return Matches(accepted: acceptedItems, remaining: remaining, stale: stale)
    }

    /// Refuses a reason with fewer than ``minimumReasonLength`` non-whitespace characters.
    public static func validate(reason: String, id: String) throws(Failure) {
        guard reason.count(where: { !$0.isWhitespace }) >= minimumReasonLength else { throw .reasonTooShort(id: id) }
    }

    private static func sorted(_ entries: [Entry]) -> [Entry] {
        entries.sorted { ($0.path, $0.declaration, $0.rule, $0.id) < ($1.path, $1.declaration, $1.rule, $1.id) }
    }
}
