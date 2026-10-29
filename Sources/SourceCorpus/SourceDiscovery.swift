internal import AemiFileSystem

#if canImport(Darwin)
    internal import Darwin
#elseif canImport(Glibc)
    internal import Glibc
#endif
#if canImport(FoundationEssentials)
    internal import FoundationEssentials
#else
    internal import Foundation
#endif

/// Finds the files under a directory argument, on `AemiFileSystem.DirectoryWalk` (aemi ADR 0017): `readdir` with the
/// entry types the listing gives, four workers, every directory opened relative to the root with no link followed.
///
/// No link is descended, so no cycle can loop and no link can lead out of the walked directory:
/// - A link, to a directory or a file, whose target resolves inside the walked directory stands for that target, which
///   the walk reaches at its own path. A linked subtree is analyzed once, under its real name, and exclusion follows the
///   real location: excluding a directory excludes it under every alias, and an alias cannot hide its target.
/// - A link whose target resolves outside is dropped. A link to `/` or to a sibling checkout used to pull every Swift
///   file it reached into the corpus, and a corpus spanning two repositories has no repository to anchor fingerprints to.
/// - A dangling link that the filter accepts is still listed, so the analyzer reports it degraded rather than dropping
///   it unseen.
public enum SourceDiscovery {
    /// Entry names never descended into: build products, VCS internals and dependency checkouts.
    /// Hidden entries (a leading `.`) are skipped as well.
    public static let skippedComponents: Set<String> = [".build", ".git", "DerivedData", ".swiftpm", "checkouts"]

    /// What a walk found.
    public struct Discovery: Sendable, Equatable {
        /// The files, absolute, spelled through the directory as given, sorted.
        public let files: [String]
        /// Directories that could not be listed, spelled like the files, sorted. They contribute nothing.
        public let unreadableDirectories: [String]
        /// Entries stat'ed: those the listing did not type (none on APFS and ext4), and each candidate link, to tell a
        /// dangling one from one that leads out.
        public let statCalls: Int
    }

    /// Every `.swift` file under `directory` that `isExcluded` keeps, with what the walk could not read.
    ///
    /// `isExcluded` is asked about each file's path and each directory's path with a trailing `/`, both spelled through
    /// `directory`; an excluded directory is not entered. It is called from the walk's worker threads.
    /// - Complexity: O(*n* log *n*) in the number of entries under `directory`; each directory is read once.
    public static func discover(
        under directory: String,
        isExcluded: @escaping @Sendable (String) -> Bool = { _ in false }
    ) -> Discovery {
        walk(directory, isExcluded: isExcluded) { $0.hasSuffix(".swift") }
    }

    /// Every `.swift` file under `directory` that `isExcluded` keeps, sorted: ``discover(under:isExcluded:)``'s files.
    ///
    /// Paths are absolute and spelled through `directory` as given; ``SourcePath`` canonicalizes them for analysis.
    public static func swiftFiles(
        under directory: String,
        isExcluded: @escaping @Sendable (String) -> Bool = { _ in false }
    ) -> [String] {
        discover(under: directory, isExcluded: isExcluded).files
    }

    /// The files under `directory` that `isIncluded` accepts and `isExcluded` keeps, walked as
    /// ``discover(under:isExcluded:)`` walks, sorted.
    public static func files(
        under directory: String,
        isExcluded: @escaping @Sendable (String) -> Bool = { _ in false },
        where isIncluded: @escaping @Sendable (String) -> Bool
    ) -> [String] {
        walk(directory, isExcluded: isExcluded, where: isIncluded).files
    }

    private static func walk(
        _ directory: String,
        isExcluded: @escaping @Sendable (String) -> Bool,
        where isIncluded: @escaping @Sendable (String) -> Bool
    ) -> Discovery {
        let root = URL(fileURLWithPath: directory).path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        let policy = DirectoryWalk.Policy(
            skippedNames: skippedComponents, includesHidden: false, links: .withinRoot,
            accepts: { candidate in
                let path = prefix + candidate.relativePath
                switch candidate.kind {
                case .directory: return !isExcluded(path + "/")
                // Under `withinRoot`, a link left is dangling or leads out; which one is decided below.
                case .file, .link: return isIncluded(path) && !isExcluded(path)
                case .other: return false
                }
            })
        guard let result = try? DirectoryWalk.walk(root, policy: policy) else {
            return Discovery(files: [], unreadableDirectories: [root], statCalls: 0)
        }
        var statCalls = result.statistics.statCalls
        var files: [String] = []
        for entry in result.entries {
            let path = prefix + entry.relativePath
            if entry.kind == .link {
                statCalls += 1
                guard !resolves(path) else { continue }
            }
            files.append(path)
        }
        let unreadable = result.failures.map { $0.relativePath.isEmpty ? root : prefix + $0.relativePath }
        return Discovery(files: files.sorted(), unreadableDirectories: unreadable.sorted(), statCalls: statCalls)
    }

    /// Whether `path`'s links lead to something that exists.
    private static func resolves(_ path: String) -> Bool {
        var status = stat()
        return unsafe stat(path, &status) == 0
    }
}
