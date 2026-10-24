internal import AemiKernel

#if canImport(FoundationEssentials)
    internal import FoundationEssentials
#else
    internal import Foundation
#endif

/// Identifies the running build of a tool, so its facts cache can tell the facts this build extracted from
/// those another build did.
///
/// Facts are a function of the extraction code. A version bumped by hand cannot tell a build from a later
/// commit that changed extraction, which then read an older build's facts as its own and reported stale
/// findings, silently. A build is identified by its executable file: path, device, inode, size and
/// modification time. Rebuilding or reinstalling changes at least one, and reading them costs one `stat` per
/// run. The price is one cold run after an executable is replaced by an identical copy.
public enum BuildIdentity {
    /// The running build's identity, or nil when its executable cannot be examined, in which case no cache
    /// is trusted.
    public static let current: String? = identity(ofExecutableAt: executablePath)

    /// A short key over the file identity of the executable at `path`, or nil when there is none.
    public static func identity(ofExecutableAt path: String?) -> String? {
        guard let path else { return nil }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolved),
            let modified = attributes[.modificationDate] as? Date
        else { return nil }
        let parts: [String] = [
            resolved,
            String(describing: attributes[.systemNumber] ?? ""),
            String(describing: attributes[.systemFileNumber] ?? ""),
            String(describing: attributes[.size] ?? ""),
            String(modified.timeIntervalSince1970),
        ]
        return String(XXH64.hash(Array(parts.joined(separator: "\0").utf8)), radix: 16)
    }

    private static var executablePath: String? {
        #if os(Linux)
            // The kernel's link to the running image; argv[0] may be relative, or a name found on PATH.
            try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/self/exe")
        #else
            Bundle.main.executablePath
        #endif
    }
}
