internal import AemiFileSystem
internal import AemiIO
internal import AemiKernel
internal import AemiRuntime
internal import Foundation
internal import Synchronization

/// A bounded copy of a tree with its content identity: every regular file's SHA-256 in a manifest, links and special
/// files refused, never followed (ADR-0030).
///
/// The copy a tool builds or tests in when the original must stay untouched (Litmus's mutation workspace, an index
/// store built in isolation). Files are cloned where the file system can (APFS: metadata only), so the copy costs the
/// hashing, not the bytes. It isolates against a tool's own mistakes; it is not a sandbox against the code it runs.
public enum TreeSnapshot {
    /// One regular file.
    public struct Entry: Sendable, Hashable, Codable {
        /// Relative to the root, `/`-separated.
        public let path: String
        public let size: Int
        /// Lower-case hexadecimal SHA-256 of the contents.
        public let sha256: String

        public init(path: String, size: Int, sha256: String) {
            self.path = path
            self.size = size
            self.sha256 = sha256
        }
    }

    /// Every regular file of a tree, sorted by path, and one digest over them all.
    public struct Manifest: Sendable, Equatable {
        public let entries: [Entry]
        /// The directories, relative, sorted.
        public let directories: [String]

        public init(entries: [Entry], directories: [String]) {
            self.entries = entries.sorted { $0.path < $1.path }
            self.directories = directories.sorted()
        }

        /// SHA-256 over `path NUL sha256 LF` of every entry in order: equal trees, equal digests.
        public var digest: String {
            var bytes: [UInt8] = []
            for entry in entries { bytes += Array(entry.path.utf8) + [0] + Array(entry.sha256.utf8) + [0x0A] }
            return ContentDigest.sha256Hex(bytes)
        }

        public var totalBytes: Int { entries.reduce(0) { $0 + $1.size } }
    }

    /// What a snapshot reads and how far.
    public struct Limits: Sendable, Equatable {
        /// Names neither copied nor entered.
        public var skippedNames: Set<String> = [".git", ".build", ".swiftpm", "DerivedData", "node_modules"]
        public var maxEntries = 150_000
        public var maxFiles = 100_000
        public var maxFileBytes = 128 << 20
        public var maxTotalBytes = 8 << 30
        /// Files copied or hashed at once.
        public var jobs = 8

        public init() {}
    }

    /// Why a snapshot was refused or failed; the partial copy is removed first.
    public struct Failure: Error, Sendable, Equatable, CustomStringConvertible {
        public let reason: String
        public init(_ reason: String) { self.reason = reason }
        public var description: String { "snapshot: \(reason)" }
    }

    /// How a tree differs from a manifest.
    public enum Difference: Sendable, Hashable {
        case added(String)
        case removed(String)
        case changed(String)
    }

    /// The manifest of `root` as it is.
    public static func inventory(_ root: String, limits: Limits = Limits()) async throws(Failure) -> Manifest {
        let root = SourcePath.canonical(root)
        let (directories, files) = try listing(root, limits: limits)
        let entries = try await hashed(files, root: root, limits: limits) { _ in }
        return Manifest(entries: entries, directories: directories)
    }

    /// Copies `source` to `destination`, which must not exist and must lie outside `source`, and returns the
    /// manifest of what was copied and how many files were cloned rather than read and written.
    public static func copy(
        from source: String,
        to destination: String,
        limits: Limits = Limits()
    ) async throws(Failure) -> (manifest: Manifest, cloned: Int) {
        let source = SourcePath.canonical(source)
        let destination = SourcePath.canonical(destination)
        let files = FileManager.default
        guard source != "/", destination != source, !destination.hasPrefix(source + "/"),
            !files.fileExists(atPath: destination), files.fileExists(atPath: source + "/")
        else { throw Failure("the destination must be new and outside the source directory") }
        do {
            try files.createDirectory(atPath: destination, withIntermediateDirectories: false)
        } catch {
            throw Failure("cannot create \(destination): \(error)")
        }
        do throws(Failure) {
            let (directories, paths) = try listing(source, limits: limits)
            for directory in directories {
                do {
                    try files.createDirectory(atPath: destination + "/" + directory, withIntermediateDirectories: false)
                } catch {
                    throw Failure("cannot create \(directory): \(error)")
                }
            }
            let cloned = Counter()
            let entries = try await hashed(paths, root: source, limits: limits) { relative throws(Failure) in
                do {
                    if try FileCopy.copy(from: source + "/" + relative, to: destination + "/" + relative) == .cloned {
                        cloned.increment()
                    }
                } catch {
                    throw Failure("cannot copy \(relative): \(error)")
                }
            }
            return (Manifest(entries: entries, directories: directories), cloned.value)
        } catch {
            try? files.removeItem(atPath: destination)
            throw error
        }
    }

    /// How `root` differs from `manifest`, by path; empty when it is the same tree.
    public static func verify(
        _ root: String,
        against manifest: Manifest,
        limits: Limits = Limits()
    ) async throws(Failure) -> [Difference] {
        let current = try await inventory(root, limits: limits)
        let before = Dictionary(manifest.entries.map { ($0.path, $0.sha256) }, uniquingKeysWith: { first, _ in first })
        let after = Dictionary(current.entries.map { ($0.path, $0.sha256) }, uniquingKeysWith: { first, _ in first })
        var differences: [Difference] = []
        for (path, digest) in before {
            if let now = after[path] {
                if now != digest { differences.append(.changed(path)) }
            } else {
                differences.append(.removed(path))
            }
        }
        for path in after.keys where before[path] == nil { differences.append(.added(path)) }
        return differences.sorted { "\($0)" < "\($1)" }
    }

    /// The directories and regular files under `root`, relative and sorted; a link or a special file is refused.
    private static func listing(_ root: String, limits: Limits) throws(Failure) -> ([String], [String]) {
        let policy = DirectoryWalk.Policy(
            skippedNames: limits.skippedNames,
            includesHidden: true,
            links: .never,
            reportsDirectories: true,
            limit: limits.maxEntries + 1,
            workers: 4
        )
        let walk: DirectoryWalk.Result
        do {
            walk = try DirectoryWalk.walk(root, policy: policy)
        } catch {
            throw Failure("cannot read \(root): \(error)")
        }
        guard !walk.limited else { throw Failure("more than \(limits.maxEntries) entries") }
        guard walk.failures.isEmpty else {
            throw Failure("cannot read \(walk.failures.map(\.relativePath).joined(separator: ", "))")
        }
        var directories: [String] = []
        var files: [String] = []
        for entry in walk.entries {
            switch entry.kind {
            case .directory: directories.append(entry.relativePath)
            case .file: files.append(entry.relativePath)
            case .link: throw Failure("refusing a link: \(entry.relativePath)")
            case .other: throw Failure("refusing a special file: \(entry.relativePath)")
            }
        }
        guard files.count <= limits.maxFiles else { throw Failure("more than \(limits.maxFiles) files") }
        return (directories.sorted(), files.sorted())
    }

    /// The entries of `files` under `root`, each hashed after `each` ran for it, at most `limits.jobs` at once.
    private static func hashed(
        _ files: [String],
        root: String,
        limits: Limits,
        each: @Sendable @escaping (String) throws(Failure) -> Void
    ) async throws(Failure) -> [Entry] {
        let entries: [Entry]
        do {
            entries = try await mapConcurrently(files, limit: limits.jobs) { relative in
                try each(relative)
                let bytes = try BoundedFileReader.read(path: root + "/" + relative, cap: limits.maxFileBytes)
                return Entry(path: relative, size: bytes.count, sha256: ContentDigest.sha256Hex(bytes))
            }
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure("\(error)")
        }
        let total = entries.reduce(0) { $0 + $1.size }
        guard total <= limits.maxTotalBytes else { throw Failure("more than \(limits.maxTotalBytes) bytes") }
        return entries
    }

    private final class Counter: Sendable {
        private let count = Mutex(0)
        func increment() { count.withLock { $0 += 1 } }
        var value: Int { count.withLock { $0 } }
    }
}
