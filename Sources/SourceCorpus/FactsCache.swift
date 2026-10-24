internal import AemiJSON

#if canImport(FoundationEssentials)
    public import FoundationEssentials
#else
    public import Foundation
#endif

/// Per-file facts cache. Parsing and extraction dominate an analyzer's run time; rules are cheap and always
/// re-run, so only facts are cached and findings never go stale relative to a rule or configuration change.
///
/// The cache is an optimization, so it **fails open**: an unreadable, corrupt or mismatched cache behaves as
/// empty and is overwritten on persist. Entries are keyed by absolute path and validated by a
/// ``ContentFingerprint``. A cache written by another build (``BuildIdentity``) is discarded whole, even one
/// of the same version, since its extraction code may differ.
///
/// The header line is plain text, compared byte for byte before any decoder reads the file, so a cache from
/// another build, or a file that is no cache at all, is never decoded. It does not validate the payload: a
/// truncated or wrongly shaped payload is a reported miss, and the next persist replaces the file.
public struct FactsCache<Facts: Codable & Sendable>: Sendable {
    /// Which tool wrote the cache, and which build of it.
    public struct Identity: Sendable, Equatable {
        public let tool: String
        public let version: String
        public let build: String

        public init(tool: String, version: String, build: String) {
            self.tool = tool
            self.version = version
            self.build = build
        }

        /// The identity of the running build, or nil when it has none and no cache can be trusted.
        public static func current(tool: String, version: String) -> Identity? {
            BuildIdentity.current.map { Identity(tool: tool, version: version, build: $0) }
        }

        var header: String { "\(tool) facts \(version) \(build)\n" }
    }

    /// One file's facts and the fingerprint they were extracted under.
    public struct Entry: Sendable, Codable {
        public let fingerprint: String
        public let facts: Facts

        public init(fingerprint: String, facts: Facts) {
            self.fingerprint = fingerprint
            self.facts = facts
        }
    }

    private struct Payload: Codable {
        var entries: [String: Entry]
    }

    /// The largest cache file read or written. `persist` holds to the same cap, so it never writes a file
    /// `load` refuses.
    public static var maxCacheBytes: Int { 64 << 20 }

    public private(set) var entries: [String: Entry]

    /// Why the file ``load(url:identity:)`` found was not used, when that is worth telling the user: it could
    /// not be read, or it was this build's cache and still did not decode. Nil for a hit, and for the ordinary
    /// misses: no file yet, or one another build wrote.
    public private(set) var loadFailure: String?

    public init(entries: [String: Entry] = [:]) {
        self.entries = entries
    }

    private init(loadFailure: String) {
        entries = [:]
        self.loadFailure = loadFailure
    }

    /// The facts cached for `path`, when they were extracted from content with `fingerprint`.
    public func facts(for path: String, fingerprint: String) -> Facts? {
        guard let entry = entries[path], entry.fingerprint == fingerprint else { return nil }
        return entry.facts
    }

    public mutating func update(path: String, fingerprint: String, facts: Facts) {
        entries[path] = Entry(fingerprint: fingerprint, facts: facts)
    }

    /// Fail-open load: any failure, including an over-cap file, returns an empty cache.
    /// - Parameters:
    ///   - url: the cache file.
    ///   - identity: the build reading; a cache another build wrote is empty to it. With none, no cache is trusted.
    /// - Complexity: O(*n*) in the file size.
    public static func load(url: URL, identity: Identity?) -> FactsCache {
        guard let identity, FileManager.default.fileExists(atPath: url.path) else { return FactsCache() }
        let bytes: [UInt8]
        do {
            bytes = try BoundedFileReader.read(path: url.path, cap: maxCacheBytes)
        } catch {
            return FactsCache(loadFailure: "ignored the facts cache at \(url.path): \(error)")
        }
        let header = Array(identity.header.utf8)
        guard bytes.starts(with: header) else { return FactsCache() }
        do {
            let payload = try AemiJSON.JSONDecoder().decode(Payload.self, from: Array(bytes[header.count...]))
            return FactsCache(entries: payload.entries)
        } catch {
            return FactsCache(
                loadFailure: "ignored the facts cache at \(url.path), which could not be decoded: \(error)")
        }
    }

    /// Best-effort persist: creates the directory, writes atomically, and swallows failures, since a
    /// read-only cache location must never fail a run. With no identity nothing is written.
    ///
    /// An over-cap cache is removed instead of written: it could never load, and an older file no longer
    /// describes this corpus.
    public func persist(url: URL, identity: Identity?) {
        guard let identity, let body = try? AemiJSON.JSONEncoder().encodeToBytes(Payload(entries: entries)) else {
            return
        }
        let header = Array(identity.header.utf8)
        guard header.count + body.count <= Self.maxCacheBytes else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(header + body).write(to: url, options: .atomic)
    }
}
