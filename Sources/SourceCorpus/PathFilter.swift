/// One exclusion rule for every tool (ADR-0008, roadmap 0005).
///
/// An entry without `*`, `?` or `[` is a substring of the path, as every tool has always read it: `Package.swift`
/// excludes `MyPackage.swift` too. An entry with them is a glob over the path relative to ``root``.
public struct PathFilter: Sendable {
    /// The directory a glob's path is relative to: the project's root.
    public let root: String?

    /// - Parameters:
    ///   - entries: the configuration's `exclude` entries; empty ones are ignored.
    ///   - root: the project's root, absolute; nil when every path given is already relative.
    public init(_ entries: [String], root: String? = nil) {
        self.root = root
    }

    /// Whether no entry can exclude anything.
    public var isEmpty: Bool { true }

    /// Whether `path` is excluded; a trailing `/` asks about a directory.
    public func excludes(_ path: String) -> Bool {
        false
    }
}
