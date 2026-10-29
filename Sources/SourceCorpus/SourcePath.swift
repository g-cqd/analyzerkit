#if canImport(FoundationEssentials)
    internal import FoundationEssentials
#else
    internal import Foundation
#endif

/// Canonical spelling of a source path.
///
/// A finding's path is part of every analyzer's output contract: it is hashed into the fingerprint a
/// baseline matches on. So one file must have one spelling however the corpus was named on the command
/// line: `a.swift`, `./a.swift` and `/abs/a.swift` are one file, analyzed once, fingerprinted identically.
/// Otherwise a baseline written from a directory walk suppresses nothing under explicit file arguments,
/// and a file named twice enters the corpus twice.
public enum SourcePath {
    /// The absolute, lexically standardized form with symlinks resolved, so a linked spelling and the real
    /// one are one corpus entry and a scope entry spelled through `/tmp` matches a corpus under `/private/tmp`.
    ///
    /// `.standardized` collapses `.` and `..` lexically, before the symlinks are resolved, so `..` is not
    /// resolved through a symlinked directory (`a/link/../b` becomes `a/b` even when `link` points
    /// elsewhere): the trade SwiftPM and SwiftLint make, and one no `git diff` output can trigger.
    /// - Complexity: O(*d*) in the path's components, plus one `realpath`-class lookup.
    public static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).standardized.resolvingSymlinksInPath().path
    }

    /// Canonicalizes every path and drops repeats, keeping first-seen order so the corpus is deterministic
    /// for a given argument list.
    /// - Complexity: O(*n*) canonicalizations and hash insertions.
    public static func canonicalized(_ paths: [String]) -> [String] { canonicalized(paths, resolve: canonical) }

    /// ``canonicalized(_:)`` with the full resolution given, so a test can count it. Red stub (roadmap 0016): every path
    /// is resolved whole.
    static func canonicalized(_ paths: [String], resolve: (String) -> String) -> [String] {
        var seen: Set<String> = []
        seen.reserveCapacity(paths.count)
        var result: [String] = []
        result.reserveCapacity(paths.count)
        for path in paths {
            let canonical = resolve(path)
            if seen.insert(canonical).inserted {
                result.append(canonical)
            }
        }
        return result
    }
}
