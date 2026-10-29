public import ProjectModel

/// Where an index store is, read from the file system without writing to it (ADR-0004, roadmap 0010).
public enum IndexStoreLocation {
    /// What a path given as an index store turned out to be.
    public enum Resolution: Sendable, Equatable {
        /// The store's root, canonical: the directory IndexStoreDB is given, holding `vN/records` and `vN/units` (or
        /// `records` and `units` directly).
        case store(String)
        /// Nothing at or below the path is a store; `reason` says what to pass instead.
        case notAStore(path: String, reason: String)
    }

    /// The store `path` names: the store itself, one of its `vN` directories, Xcode's `Index.noindex` or a DerivedData
    /// build root above it, or a SwiftPM `.build` directory or build configuration holding `index/store`. Reads only.
    public static func resolve(_ path: String) -> Resolution { .notAStore(path: path, reason: "") }

    /// The store for a project: SwiftPM's under the layout root's `.build` first, then the newest DerivedData store
    /// whose workspace is one of the layout's containers. Nil when there is none.
    public static func discover(layout: ProjectLayout, derivedDataRoots: [String]) -> String? { nil }

    /// Where the database for `store` lives: `<cacheRoot>/index/<hash of the store's canonical path>`, so every tool that
    /// shares a cache root shares the database, and nothing is written next to the store.
    public static func databaseDirectory(forStore store: String, cacheRoot: String) -> String { cacheRoot }
}
