internal import AemiRuntime
internal import SourceCorpus

#if canImport(FoundationEssentials)
    public import FoundationEssentials
#else
    public import Foundation
#endif

/// One file's outcome in a ``CorpusScan``.
public struct ScannedFile<Facts: Sendable>: Sendable {
    public let path: String
    /// The facts, from the cache or freshly extracted; nil when the file could not be read.
    public let facts: Facts?
    /// The content fingerprint the facts belong to; nil when the file could not be read.
    public let fingerprint: String?
    public let cacheHit: Bool
    /// Why the file could not be read, so the analyzer reports it degraded rather than dropping it unseen.
    public let failure: String?
}

/// What ``CorpusScanner/scan(paths:cacheURL:identity:salt:width:extract:)`` found.
public struct CorpusScan<Facts: Codable & Sendable>: Sendable {
    /// One entry per distinct canonical path, sorted by path.
    public let files: [ScannedFile<Facts>]
    public let cacheHits: Int
    public var cacheMisses: Int { files.count - cacheHits }
    /// See ``FactsCache/loadFailure``.
    public let cacheLoadFailure: String?
}

/// The pipeline every analyzer runs before its rules: canonicalize, read, fingerprint, reuse cached facts or
/// extract, and persist the cache.
public enum CorpusScanner {
    /// Scans `paths`, extracting facts from each file in parallel.
    ///
    /// Fan-out is bounded to `width` files in flight (Aemi's `mapConcurrently`), so descriptor pressure and
    /// peak memory do not grow with the corpus. `extract` runs on the cooperative pool and must not block on
    /// anything but its own file. A cancelled caller stops scheduling files and the scan throws
    /// `CancellationError`; the cache is not touched.
    ///
    /// The cache serves one workspace across runs: a run over part of it keeps the other entries, and only
    /// entries whose file is gone are pruned. It is rewritten only when something changed.
    ///
    /// - Parameters:
    ///   - paths: the files, in any spelling; they are canonicalized and deduplicated.
    ///   - cacheURL: the cache file, or nil for no cache.
    ///   - identity: the build reading and writing the cache; nil trusts no cache.
    ///   - salt: what else the facts depend on, mixed into every fingerprint.
    ///   - width: the most files in flight; below one behaves as one.
    ///   - extract: facts from a file's path and bytes.
    /// - Throws: `CancellationError`.
    /// - Complexity: O(*n*) in the corpus size over `width` workers, plus the cache's load and persist.
    public static func scan<Facts: Codable & Sendable>(
        paths: [String],
        cacheURL: URL? = nil,
        identity: FactsCache<Facts>.Identity? = nil,
        salt: String = "",
        width: Int = ProcessInfo.processInfo.activeProcessorCount,
        extract: @escaping @Sendable (_ path: String, _ bytes: [UInt8]) -> Facts
    ) async throws -> CorpusScan<Facts> {
        let canonical = SourcePath.canonicalized(paths)
        let snapshot = cacheURL.map { FactsCache<Facts>.load(url: $0, identity: identity) } ?? FactsCache<Facts>()
        let files = try await mapConcurrently(canonical, limit: width) { path in
            outcome(for: path, snapshot: snapshot, salt: salt, extract: extract)
        }.sorted { $0.path < $1.path }

        let hits = files.reduce(0) { $0 + ($1.cacheHit ? 1 : 0) }
        if let cacheURL {
            persist(files, hits: hits, snapshot: snapshot, to: cacheURL, identity: identity)
        }
        return CorpusScan(files: files, cacheHits: hits, cacheLoadFailure: snapshot.loadFailure)
    }

    private static func outcome<Facts: Codable & Sendable>(
        for path: String,
        snapshot: FactsCache<Facts>,
        salt: String,
        extract: @Sendable (String, [UInt8]) -> Facts
    ) -> ScannedFile<Facts> {
        let bytes: [UInt8]
        do {
            bytes = try BoundedFileReader.read(path: path, cap: BoundedFileReader.sourceByteCap)
        } catch {
            return ScannedFile(path: path, facts: nil, fingerprint: nil, cacheHit: false, failure: "\(error)")
        }
        let fingerprint = ContentFingerprint.of(bytes, salt: salt)
        if let cached = snapshot.facts(for: path, fingerprint: fingerprint) {
            return ScannedFile(path: path, facts: cached, fingerprint: fingerprint, cacheHit: true, failure: nil)
        }
        return ScannedFile(
            path: path, facts: extract(path, bytes), fingerprint: fingerprint, cacheHit: false, failure: nil)
    }

    /// Writes the snapshot's surviving entries overlaid with this run's, unless that would rewrite the cache
    /// exactly as it is: every file hit, nothing pruned, and the old cache loaded cleanly (a cache that failed
    /// to load must be replaced even when this run parsed nothing, or every later run would report it again).
    private static func persist<Facts: Codable & Sendable>(
        _ files: [ScannedFile<Facts>],
        hits: Int,
        snapshot: FactsCache<Facts>,
        to url: URL,
        identity: FactsCache<Facts>.Identity?
    ) {
        var persisted = FactsCache<Facts>()
        var current: Set<String> = []
        current.reserveCapacity(files.count)
        for file in files {
            guard let facts = file.facts, let fingerprint = file.fingerprint else { continue }
            persisted.update(path: file.path, fingerprint: fingerprint, facts: facts)
            current.insert(file.path)
        }
        var pruned = false
        for (path, entry) in snapshot.entries where !current.contains(path) {
            if FileManager.default.fileExists(atPath: path) {
                persisted.update(path: path, fingerprint: entry.fingerprint, facts: entry.facts)
            } else {
                pruned = true
            }
        }
        let unchanged = hits == files.count && !pruned && snapshot.loadFailure == nil && !snapshot.entries.isEmpty
        if !unchanged { persisted.persist(url: url, identity: identity) }
    }
}
