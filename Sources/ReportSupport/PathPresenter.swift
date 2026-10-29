internal import SourceCorpus

/// How a report spells paths relative to a directory (`--relative-to`), the rule every analyzer shares: a path inside
/// the directory loses its prefix, a path outside stays absolute (never a `../..` chain no consumer resolves usefully),
/// and free text (a message, a note, a degraded file's detail) loses the prefix wherever it quotes a path, so one report
/// never mixes both spellings. Which fields a tool passes through it stays the tool's choice.
public struct PathPresenter: Sendable {
    /// The canonical directory, as `SourcePath` spells analyzed files.
    public let root: String

    public init(root: String) {
        self.root = root
    }

    /// `path` relative to ``root`` when inside it, else unchanged.
    public func path(_ path: String) -> String { path }

    /// `text` with every occurrence of ``root`` followed by a separator removed.
    public func text(_ text: String) -> String { text }
}
