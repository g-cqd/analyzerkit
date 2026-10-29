#if canImport(FoundationEssentials)
    internal import FoundationEssentials
#else
    internal import Foundation
#endif

/// Finds the files under a directory argument.
///
/// The walk follows symlinks, so a linked subtree is analyzed like any other, within two limits:
/// - Each directory is entered once, identified by the device and inode its path resolves to. A link back
///   to an ancestor (`ln -s ..`) used to send the walk round the tree again at every level until the
///   kernel's symlink limit, and two such links made it exponential.
/// - A link, to a directory or to a file, whose target resolves outside the walked directory is not
///   followed. A link to `/` or to a sibling checkout used to pull every Swift file it reached into the
///   corpus, and a corpus spanning two repositories has no repository to anchor fingerprints to.
///
/// A dangling link that the filter accepts is still listed, so the analyzer reports it degraded rather than
/// dropping it unseen.
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
        /// Entries the directory listing did not type, so they were stat'ed; zero on APFS and ext4.
        public let statCalls: Int
    }

    /// Every `.swift` file under `directory` that `isExcluded` keeps, with what the walk could not read.
    public static func discover(
        under directory: String,
        isExcluded: @escaping @Sendable (String) -> Bool = { _ in false }
    ) -> Discovery {
        // Red stub (roadmap 0007): today's walk, which stats every entry and cannot tell an unreadable directory.
        let files = swiftFiles(under: directory, isExcluded: isExcluded)
        return Discovery(files: files, unreadableDirectories: [], statCalls: -1)
    }

    /// Every `.swift` file under `directory` that `isExcluded` keeps, sorted.
    ///
    /// Paths are absolute and spelled through `directory` as given; ``SourcePath`` canonicalizes them for
    /// analysis. Entries are visited in name order, so the spelling a file is listed under does not depend on
    /// directory order. An unreadable directory contributes nothing.
    ///
    /// `isExcluded` is asked about each file's path as it was reached, and about each directory's with a
    /// trailing `/`. An excluded directory is not walked and does not count as visited, so a link named like
    /// an exclude pattern cannot hide the real directory behind it.
    /// - Complexity: O(*n* log *n*) in the number of entries under `directory`; each directory is read once.
    public static func swiftFiles(under directory: String, isExcluded: (String) -> Bool = { _ in false }) -> [String] {
        files(under: directory, isExcluded: isExcluded) { $0.hasSuffix(".swift") }
    }

    /// The files under `directory` that `isIncluded` accepts and `isExcluded` keeps, walked as
    /// ``swiftFiles(under:isExcluded:)`` walks, sorted.
    public static func files(
        under directory: String,
        isExcluded: (String) -> Bool = { _ in false },
        where isIncluded: (String) -> Bool
    ) -> [String] {
        let manager = FileManager.default
        let root = SourcePath.canonical(directory)
        let rootPrefix = root.hasSuffix("/") ? root : root + "/"
        var visited: Set<DirectoryIdentity> = []
        if let attributes = try? manager.attributesOfItem(atPath: root) {
            visited.insert(DirectoryIdentity(attributes: attributes, resolvedPath: root))
        }

        var files: [String] = []
        // Each directory as the caller spells it, and as it resolves: an entry's own location is its
        // directory's resolved path plus its name, so only an entry that is itself a link needs resolving.
        var stack = [(spelled: URL(fileURLWithPath: directory).path, resolved: root)]
        while let current = stack.popLast() {
            guard let entries = try? manager.contentsOfDirectory(atPath: current.spelled) else { continue }
            for entry in entries.sorted() where !entry.hasPrefix(".") && !skippedComponents.contains(entry) {
                let spelled = joined(current.spelled, entry)
                var resolved = joined(current.resolved, entry)
                // attributesOfItem does not follow a final symlink.
                var attributes = try? manager.attributesOfItem(atPath: resolved)
                if (attributes?[.type] as? FileAttributeType) == .typeSymbolicLink {
                    // A dangling link does not resolve, and keeps its own location.
                    resolved = SourcePath.canonical(resolved)
                    guard resolved == root || resolved.hasPrefix(rootPrefix) else { continue }
                    attributes = try? manager.attributesOfItem(atPath: resolved)
                }
                if let attributes, (attributes[.type] as? FileAttributeType) == .typeDirectory {
                    guard !isExcluded(spelled + "/"),
                        visited.insert(DirectoryIdentity(attributes: attributes, resolvedPath: resolved)).inserted
                    else { continue }
                    stack.append((spelled, resolved))
                } else if isIncluded(spelled), !isExcluded(spelled) {
                    files.append(spelled)
                }
            }
        }
        return files.sorted()
    }

    /// `name` inside `directory`, with one separator even when `directory` is `/`.
    private static func joined(_ directory: String, _ name: String) -> String {
        directory.hasSuffix("/") ? directory + name : directory + "/" + name
    }

    /// What makes two spellings one directory: the device and inode its path resolves to, or the resolved
    /// path when the file system reports neither.
    private enum DirectoryIdentity: Hashable {
        case node(device: UInt64, inode: UInt64)
        case path(String)

        init(attributes: [FileAttributeKey: Any], resolvedPath: String) {
            if let device = Self.number(attributes[.systemNumber]),
                let inode = Self.number(attributes[.systemFileNumber])
            {
                self = .node(device: device, inode: inode)
            } else {
                self = .path(resolvedPath)
            }
        }

        /// Foundation boxes these attributes as `NSNumber` on Darwin, and as `UInt` or `UInt64` in
        /// FoundationEssentials.
        private static func number(_ value: Any?) -> UInt64? {
            switch value {
            case let number as UInt64: number
            case let number as UInt: UInt64(number)
            case let number as Int: UInt64(exactly: number)
            default: nil
            }
        }
    }
}
