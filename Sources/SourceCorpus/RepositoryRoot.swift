internal import AemiKernel

#if canImport(FoundationEssentials)
    internal import FoundationEssentials
#else
    internal import Foundation
#endif

/// Finds the repository a corpus lives in, so fingerprints can be made location-independent without the
/// caller asking for it.
///
/// A fingerprint that hashes an absolute path matches nothing on another machine, and a fingerprint that
/// matches nothing looks exactly like a finding that is genuinely new. Inside a repository the fingerprint
/// hashes the path relative to the repository root, found here; outside one it keeps the absolute path,
/// since there is no better anchor.
public enum RepositoryRoot {
    /// Walks up from `path` looking for a `.git` entry, a directory (an ordinary clone) or a file (a
    /// worktree or submodule, where `.git` is a pointer). Nil outside a repository.
    /// - Complexity: O(*d*) `stat` calls in the path's depth.
    public static func detect(from path: String) -> String? {
        detect(from: path, probing: gitEntryExists)
    }

    /// ``detect(from:)`` with the `.git` existence check supplied, so tests can count the probes.
    static func detect(from path: String, probing exists: (String) -> Bool) -> String? {
        var known: [String: String?] = [:]
        return detect(from: path, probing: exists, known: &known)
    }

    /// Walks up from `path` until a directory holds `.git` or was already answered in `known`, then records the answer
    /// for every directory it passed, so a later path below any of them stops there.
    /// - Complexity: O(*d*) probes for the directories not yet in `known`.
    private static func detect(
        from path: String, probing exists: (String) -> Bool, known: inout [String: String?]
    ) -> String? {
        var directory = URL(fileURLWithPath: path).standardized
        if directory.pathExtension == "swift" || !directory.hasDirectoryPath {
            directory = directory.deletingLastPathComponent()
        }
        var passed: [String] = []
        var root: String?
        while directory.path != "/" && !directory.path.isEmpty {
            if let answer = known[directory.path] {
                root = answer
                break
            }
            passed.append(directory.path)
            if exists(directory.appendingPathComponent(".git").path) {
                root = directory.path
                break
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }
        for directory in passed { known[directory] = .some(root) }
        return root
    }

    private static func gitEntryExists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    /// The root shared by every file in `corpus`, or nil if they disagree: the corpus spans repositories
    /// (or none), and no single anchor makes every fingerprint portable.
    /// - Complexity: one `.git` probe per distinct directory of the corpus and of the directories above them, up to
    ///   the root found; not one per file.
    public static func common(of corpus: [String]) -> String? {
        common(of: corpus, probing: gitEntryExists)
    }

    /// ``common(of:)`` with the `.git` existence check supplied, so tests can count the probes.
    static func common(of corpus: [String], probing exists: (String) -> Bool) -> String? {
        var found: String?
        var known: [String: String?] = [:]
        for path in corpus {
            guard let root = detect(from: path, probing: exists, known: &known) else { return nil }
            if let found, found != root { return nil }
            found = root
        }
        return found
    }

    /// `path` expressed relative to `root`, or unchanged when it lies outside.
    public static func relativize(_ path: String, to root: String) -> String {
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(prefix) else { return path }
        return String(path.dropFirst(prefix.count))
    }

    /// A short, filesystem-safe key for the repository `directory` belongs to (or the directory itself,
    /// outside one), so each workspace gets its own cache and alternating projects still hit.
    public static func workspaceKey(from directory: String) -> String {
        let root = detect(from: directory + "/.") ?? directory
        return String(XXH64.hash(Array(root.utf8)), radix: 16)
    }
}
