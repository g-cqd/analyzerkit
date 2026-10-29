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

/// What ``CorpusScanner/scan(paths:cache:identity:salt:width:extract:)`` found.
public struct CorpusScan<Facts: Codable & Sendable>: Sendable {
    /// One entry per distinct canonical path, sorted by path.
    public let files: [ScannedFile<Facts>]
    public let cacheHits: Int
    public var cacheMisses: Int { files.count - cacheHits }
    /// How many source files were opened and read: a warm run whose stat keys match reads none.
    public let filesRead: Int
    /// Why the cache, or part of it, was not used, when that is worth telling the user.
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
    ///   - cache: where the cache lives and which workspace it serves, or nil for no cache.
    ///   - identity: the build reading and writing the cache; nil trusts no cache.
    ///   - salt: what else the facts depend on, mixed into every fingerprint.
    ///   - width: the most files in flight; below one behaves as one.
    ///   - extract: facts from a file's path and bytes.
    /// - Throws: `CancellationError`.
    /// - Complexity: O(*n*) in the corpus size over `width` workers, plus the cache's load and persist.
    public static func scan<Facts: Codable & Sendable>(
        paths: [String],
        cache: CacheLocation? = nil,
        identity: CacheIdentity? = nil,
        salt: String = "",
        width: Int = ProcessInfo.processInfo.activeProcessorCount,
        extract: @escaping @Sendable (_ path: String, _ bytes: [UInt8]) -> Facts
    ) async throws -> CorpusScan<Facts> {
        // Red stub (roadmap 0016): no cache.
        let canonical = SourcePath.canonicalized(paths)
        let files = try await mapConcurrently(canonical, limit: width) { path in
            await outcome(for: path, salt: salt, extract: extract)
        }.sorted { $0.path < $1.path }
        return CorpusScan(files: files, cacheHits: 0, filesRead: files.count, cacheLoadFailure: nil)
    }

    private static func outcome<Facts: Codable & Sendable>(
        for path: String,
        salt: String,
        extract: @escaping @Sendable (String, [UInt8]) -> Facts
    ) async -> ScannedFile<Facts> {
        let bytes: [UInt8]
        do {
            bytes = try BoundedFileReader.read(path: path, cap: BoundedFileReader.sourceByteCap)
        } catch {
            return ScannedFile(path: path, facts: nil, fingerprint: nil, cacheHit: false, failure: "\(error)")
        }
        let fingerprint = ContentFingerprint.of(bytes, salt: salt)
        let facts = await LargeStack.run { extract(path, bytes) }
        return ScannedFile(path: path, facts: facts, fingerprint: fingerprint, cacheHit: false, failure: nil)
    }
}
