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

    /// ``canonicalized(_:)`` with the full resolution given, so a test can count it.
    ///
    /// A file that exists and is not itself a link is spelled as its directory's canonical form and its name: one full
    /// resolution per directory, an `lstat` per file. Anything else (a link, a missing path, the root) is resolved whole,
    /// so every spelling is the one ``canonical(_:)`` gives.
    static func canonicalized(_ paths: [String], resolve: (String) -> String) -> [String] {
        var directories: [String: String] = [:]
        var seen: Set<String> = []
        seen.reserveCapacity(paths.count)
        var result: [String] = []
        result.reserveCapacity(paths.count)
        for path in paths {
            // Discovery hands over absolute, standard paths; only other spellings pay for `URL`'s standardization.
            let standardized = isStandardAbsolute(path) ? path : URL(fileURLWithPath: path).standardized.path
            let canonical: String
            if let slash = standardized.utf8.lastIndex(of: UInt8(ascii: "/")), slash != standardized.utf8.startIndex,
                existsWithoutLink(standardized)
            {
                let parent = String(standardized[..<slash])
                let name = String(standardized[standardized.index(after: slash)...])
                let directory: String
                if let known = directories[parent] {
                    directory = known
                } else {
                    directory = resolve(parent)
                    directories[parent] = directory
                }
                canonical = directory.hasSuffix("/") ? directory + name : directory + "/" + name
            } else {
                canonical = resolve(path)
            }
            if seen.insert(canonical).inserted {
                result.append(canonical)
            }
        }
        return result
    }

    /// Whether `path` is absolute with no empty, `.` or `..` component and no trailing separator: what `URL`'s
    /// standardization would return unchanged.
    private static func isStandardAbsolute(_ path: String) -> Bool {
        let bytes = path.utf8
        guard bytes.first == UInt8(ascii: "/"), bytes.count > 1, bytes.last != UInt8(ascii: "/") else { return false }
        var component = 0  // bytes since the last separator
        var dots = 0  // how many of them were dots
        for byte in bytes.dropFirst() {
            if byte == UInt8(ascii: "/") {
                if component == 0 || (component == dots && dots <= 2) { return false }
                component = 0
                dots = 0
            } else {
                component += 1
                if byte == UInt8(ascii: ".") { dots += 1 }
            }
        }
        return !(component == dots && dots <= 2)
    }

    /// Whether something is at `path` and it is not a symbolic link.
    private static func existsWithoutLink(_ path: String) -> Bool {
        var status = stat()
        return unsafe lstat(path, &status) == 0 && status.st_mode & S_IFMT != S_IFLNK
    }
}
