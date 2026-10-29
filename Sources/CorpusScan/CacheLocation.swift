internal import SourceCorpus

#if canImport(FoundationEssentials)
    internal import FoundationEssentials
#else
    internal import Foundation
#endif

/// Which tool wrote a cache, and which build of it: a cache another build wrote is a miss, since its extraction code may
/// differ.
public struct CacheIdentity: Sendable, Equatable {
    public let tool: String
    public let version: String
    public let build: String

    public init(tool: String, version: String, build: String) {
        self.tool = tool
        self.version = version
        self.build = build
    }

    /// The identity of the running build, or nil when it has none and no cache can be trusted.
    public static func current(tool: String, version: String) -> CacheIdentity? {
        BuildIdentity.current.map { CacheIdentity(tool: tool, version: version, build: $0) }
    }
}

/// Where a tool's cache lives, and which workspace a scan serves (ADR-0011).
public struct CacheLocation: Sendable, Equatable {
    /// The default budget for everything under the root.
    public static let defaultMaximumBytes = 512 << 20

    /// The tool's cache root: `--cache-path`, or ``defaultRoot(tool:environment:home:)``.
    public let root: String
    /// The corpus the scan serves (a project or package root); one workspace's entries are kept together.
    public let workspace: String
    /// The budget for everything under the root; least recently used workspaces, then shards, are removed above it.
    public let maximumBytes: Int

    public init(root: String, workspace: String, maximumBytes: Int = defaultMaximumBytes) {
        self.root = root
        self.workspace = workspace
        self.maximumBytes = maximumBytes
    }

    /// `~/Library/Caches/<tool>` on macOS; elsewhere `$XDG_CACHE_HOME/<tool>`, or `~/.cache/<tool>`.
    public static func defaultRoot(tool: String, environment: [String: String], home: String) -> String {
        #if os(macOS)
            return home + "/Library/Caches/" + tool
        #else
            if let xdg = environment["XDG_CACHE_HOME"], xdg.hasPrefix("/") { return xdg + "/" + tool }
            return home + "/.cache/" + tool
        #endif
    }
}
