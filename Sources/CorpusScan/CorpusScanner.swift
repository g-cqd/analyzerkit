internal import AemiKernel
public import AemiProtobuf
internal import AemiRuntime
internal import SourceCorpus

#if canImport(Darwin)
    internal import Darwin
#elseif canImport(Glibc)
    internal import Glibc
#endif

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
    /// The file's bytes, when the scan was asked to keep them (`keepingBytes`) and the file could be read.
    public let bytes: [UInt8]?

    init(
        path: String, facts: Facts?, fingerprint: String?, cacheHit: Bool, failure: String?, bytes: [UInt8]? = nil
    ) {
        self.path = path
        self.facts = facts
        self.fingerprint = fingerprint
        self.cacheHit = cacheHit
        self.failure = failure
        self.bytes = bytes
    }
}

/// What ``CorpusScanner/scan(paths:cache:identity:salt:width:extract:)`` found.
public struct CorpusScan<Facts: Sendable>: Sendable {
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
    ///   - keepingBytes: hand every readable file's bytes back in ``ScannedFile/bytes``, reading them on a stat-key hit
    ///     too, for a tool that needs the text after the scan; off, a settled hit reads nothing.
    ///   - extract: facts from a file's path and bytes.
    /// - Throws: `CancellationError`.
    /// - Complexity: O(*n*) in the corpus size over `width` workers, plus the cache's load and persist.
    public static func scan<Facts: Codable & Sendable>(
        paths: [String],
        cache: CacheLocation? = nil,
        identity: CacheIdentity? = nil,
        salt: String = "",
        width: Int = ProcessInfo.processInfo.activeProcessorCount,
        keepingBytes: Bool = false,
        extract: @escaping @Sendable (_ path: String, _ bytes: [UInt8]) -> Facts
    ) async throws -> CorpusScan<Facts> {
        try await scan(
            paths: paths, cache: cache, identity: identity, salt: salt, width: width, keepingBytes: keepingBytes,
            codec: .json, extract: extract)
    }

    /// ``scan(paths:cache:identity:salt:width:keepingBytes:extract:)`` for facts with AemiProtobuf's fast path: payloads
    /// are protobuf, about half the size of JSON and faster to decode (roadmap 0017). The codec is part of the salt, so a
    /// payload another codec wrote is never decoded.
    public static func scan<Facts: AemiProtoFastEncodable & AemiProtoFastDecodable & Sendable>(
        paths: [String],
        cache: CacheLocation? = nil,
        identity: CacheIdentity? = nil,
        salt: String = "",
        width: Int = ProcessInfo.processInfo.activeProcessorCount,
        keepingBytes: Bool = false,
        extract: @escaping @Sendable (_ path: String, _ bytes: [UInt8]) -> Facts
    ) async throws -> CorpusScan<Facts> {
        try await scan(
            paths: paths, cache: cache, identity: identity, salt: salt + PayloadCodec<Facts>.protobufSalt,
            width: width, keepingBytes: keepingBytes, codec: .protobuf, extract: extract)
    }

    /// The protobuf path for facts that are `Codable` too: the protobuf payload wins.
    public static func scan<Facts: Codable & AemiProtoFastEncodable & AemiProtoFastDecodable & Sendable>(
        paths: [String],
        cache: CacheLocation? = nil,
        identity: CacheIdentity? = nil,
        salt: String = "",
        width: Int = ProcessInfo.processInfo.activeProcessorCount,
        keepingBytes: Bool = false,
        extract: @escaping @Sendable (_ path: String, _ bytes: [UInt8]) -> Facts
    ) async throws -> CorpusScan<Facts> {
        try await scan(
            paths: paths, cache: cache, identity: identity, salt: salt + PayloadCodec<Facts>.protobufSalt,
            width: width, keepingBytes: keepingBytes, codec: .protobuf, extract: extract)
    }

    private static func scan<Facts: Sendable>(
        paths: [String],
        cache: CacheLocation?,
        identity: CacheIdentity?,
        salt: String,
        width: Int,
        keepingBytes: Bool,
        codec: PayloadCodec<Facts>,
        extract: @escaping @Sendable (_ path: String, _ bytes: [UInt8]) -> Facts
    ) async throws -> CorpusScan<Facts> {
        let canonical = SourcePath.canonicalized(paths)
        let started = Self.now()
        // The shards this run touches, mapped and indexed; no payload is decoded yet.
        var shards: [Int: Shard] = [:]
        var corrupt = 0
        let seed = salt.isEmpty ? 0 : XXH64.hash(Array(salt.utf8))
        let store = cache.flatMap { location in identity.map { (location, $0) } }
        if let (location, identity) = store {
            for index in Set(canonical.map(FactsStore.shardIndex(of:))) {
                let path = FactsStore.shardPath(location, index)
                switch Shard.load(path: path, index: index, identity: identity, salt: seed) {
                case .shard(let shard): shards[index] = shard
                case .absent: shards[index] = Shard(index: index)
                case .corrupt:
                    shards[index] = Shard(index: index, dirty: true)
                    corrupt += 1
                }
            }
        }
        let snapshot = shards
        let outcomes = try await mapConcurrently(canonical, limit: width) { path in
            await outcome(
                for: path, shard: snapshot[FactsStore.shardIndex(of: path)], seed: seed, keepingBytes: keepingBytes,
                codec: codec, extract: extract)
        }.sorted { $0.file.path < $1.file.path }
        try Task.checkCancellation()

        var notes: [String] = []
        if corrupt > 0 { notes.append("\(corrupt) cache shard(s) could not be decoded and were rebuilt") }
        if let (location, identity) = store {
            if let refusal = FactsStore.prepareRoot(location.root) {
                notes.append(refusal)
            } else {
                persist(outcomes, shards: shards, location: location, identity: identity, salt: seed, started: started)
            }
        }
        let files = outcomes.map(\.file)
        return CorpusScan(
            files: files, cacheHits: files.reduce(0) { $0 + ($1.cacheHit ? 1 : 0) },
            filesRead: outcomes.reduce(0) { $0 + ($1.read ? 1 : 0) },
            cacheLoadFailure: notes.isEmpty ? nil : notes.joined(separator: "; "))
    }

    /// One file's result, whether its bytes were read, and what its shard must record.
    private struct Outcome<Facts: Sendable>: Sendable {
        var file: ScannedFile<Facts>
        var read: Bool
        var update: StoredEntry?
    }

    /// The stat key first: a match outside the racy window is a hit with no read. Otherwise the content hash: a match is a
    /// hit (and the entry's stat key is refreshed). Otherwise the facts are extracted.
    private static func outcome<Facts: Sendable>(
        for path: String,
        shard: Shard?,
        seed: UInt64,
        keepingBytes: Bool,
        codec: PayloadCodec<Facts>,
        extract: @escaping @Sendable (String, [UInt8]) -> Facts
    ) async -> Outcome<Facts> {
        let key = StatKey.of(path)
        let entry = shard?.entries[path]
        if !keepingBytes, let shard, let entry, let key, entry.stat == key,
            entry.stat.modified < shard.writtenAt - FactsStore.racyWindow,
            let facts = codec.decode(shard.payload(of: entry))
        {
            let fingerprint = fingerprint(entry.contentHash, size: Int(key.size))
            return Outcome(
                file: ScannedFile(path: path, facts: facts, fingerprint: fingerprint, cacheHit: true, failure: nil),
                read: false, update: nil)
        }
        let bytes: [UInt8]
        do {
            bytes = try BoundedFileReader.read(path: path, cap: BoundedFileReader.sourceByteCap)
        } catch {
            return Outcome(
                file: ScannedFile(path: path, facts: nil, fingerprint: nil, cacheHit: false, failure: "\(error)"),
                read: true, update: nil)
        }
        let hash = XXH64.hash(bytes, seed: seed)
        let fingerprint = fingerprint(hash, size: bytes.count)
        if let shard, let entry, entry.contentHash == hash, let facts = codec.decode(shard.payload(of: entry)) {
            // A refreshed key lets the next run skip the read; an unchanged one is rewritten only to settle a racy entry.
            let settled = key.map { StoredEntry(stat: $0, contentHash: hash, payload: entry.payload) }
            return Outcome(
                file: ScannedFile(
                    path: path, facts: facts, fingerprint: fingerprint, cacheHit: true, failure: nil,
                    bytes: keepingBytes ? bytes : nil),
                read: true, update: settled)
        }
        // Extraction parses and walks a syntax tree, which recurses once per level; a cache hit does neither, so only
        // a miss pays for a thread with a large stack (roadmap 0041).
        let facts = await LargeStack.run { extract(path, bytes) }
        let update = key.flatMap { key in
            codec.encode(facts).map { StoredEntry(stat: key, contentHash: hash, payload: .bytes($0)) }
        }
        return Outcome(
            file: ScannedFile(
                path: path, facts: facts, fingerprint: fingerprint, cacheHit: false, failure: nil,
                bytes: keepingBytes ? bytes : nil),
            read: true, update: update)
    }

    /// ``ContentFingerprint``'s spelling, from a hash already known.
    private static func fingerprint(_ hash: UInt64, size: Int) -> String {
        String(hash, radix: 16) + "-" + String(size)
    }

    /// Applies the run's updates to its shards, prunes entries of files that are gone, writes the shards that changed,
    /// marks the workspace used, and holds the budget.
    private static func persist<Facts: Sendable>(
        _ outcomes: [Outcome<Facts>], shards: [Int: Shard], location: CacheLocation, identity: CacheIdentity,
        salt: UInt64, started: Int64
    ) {
        var scanned: Set<String> = []
        for outcome in outcomes {
            scanned.insert(outcome.file.path)
            guard let update = outcome.update, let shard = shards[FactsStore.shardIndex(of: outcome.file.path)] else {
                continue
            }
            shard.set(outcome.file.path, update)
        }
        for shard in shards.values {
            for path in shard.entries.keys
            where !scanned.contains(path) && !FileManager.default.fileExists(atPath: path) {
                shard.remove(path)
            }
        }
        let directory = FactsStore.workspaceDirectory(location)
        let dirty = shards.values.filter(\.isDirty)
        if !dirty.isEmpty {
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            let record = directory + "/workspace"
            if !FileManager.default.fileExists(atPath: record) {
                try? Data((SourcePath.canonical(location.workspace) + "\n").utf8).write(
                    to: URL(fileURLWithPath: record), options: .atomic)
            }
        }
        for shard in dirty {
            let path = FactsStore.shardPath(location, shard.index)
            if shard.entries.isEmpty {
                try? FileManager.default.removeItem(atPath: path)
            } else {
                try? Data(shard.encoded(identity: identity, salt: salt, writtenAt: started)).write(
                    to: URL(fileURLWithPath: path), options: .atomic)
            }
        }
        // The workspace's last use, for the budget's least-recently-used order.
        if FileManager.default.fileExists(atPath: directory) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: directory)
        }
        FactsStore.enforceBudget(location)
    }

    /// Nanoseconds since the epoch, the clock file modification times use.
    private static func now() -> Int64 {
        var time = timespec()
        unsafe clock_gettime(CLOCK_REALTIME, &time)
        return Int64(time.tv_sec) * 1_000_000_000 + Int64(time.tv_nsec)
    }
}
