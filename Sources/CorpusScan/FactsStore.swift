internal import AemiIO
internal import AemiKernel
internal import AemiProtobufCore
internal import SourceCorpus

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

/// A file's identity on disk, read without opening it (ADR-0011 item 2).
struct StatKey: Equatable, Sendable {
    var device: UInt64
    var inode: UInt64
    var size: UInt64
    /// Nanoseconds since the epoch.
    var modified: Int64
    var changed: Int64

    /// The key of the regular file at `path`, or nil when there is none.
    static func of(_ path: String) -> StatKey? {
        var status = stat()
        guard unsafe stat(path, &status) == 0, status.st_mode & S_IFMT == S_IFREG else { return nil }
        #if canImport(Darwin)
            let modified = status.st_mtimespec
            let changed = status.st_ctimespec
        #else
            let modified = status.st_mtim
            let changed = status.st_ctim
        #endif
        return StatKey(
            device: UInt64(truncatingIfNeeded: status.st_dev), inode: UInt64(truncatingIfNeeded: status.st_ino),
            size: UInt64(truncatingIfNeeded: status.st_size),
            modified: Int64(modified.tv_sec) * 1_000_000_000 + Int64(modified.tv_nsec),
            changed: Int64(changed.tv_sec) * 1_000_000_000 + Int64(changed.tv_nsec))
    }
}

/// One file's entry in a shard.
struct StoredEntry: Sendable {
    var stat: StatKey
    /// XXH64 of the bytes, seeded with the salt's XXH64.
    var contentHash: UInt64
    var payload: Payload

    enum Payload: Sendable {
        /// Still in the shard's mapping: decoded only on a hit, copied as is when the shard is rewritten.
        case mapped(Range<Int>)
        case bytes([UInt8])
    }
}

/// One shard file: a protobuf message holding the identity of the build that wrote it, the time its run started, and
/// its entries (ADR-0011 item 3). Mapped, and indexed without decoding any payload.
final class Shard: @unchecked Sendable {
    // Shard message: 1 tool, 2 version, 3 build (strings), 4 written-at nanoseconds (fixed64), 5 entry (repeated),
    // 6 the salt's XXH64 (fixed64): facts extracted under another salt are another build's.
    // Entry message: 1 path, 2 device, 3 inode, 4 size, 5 modified, 6 changed, 7 content hash (fixed64), 8 payload.
    let index: Int
    /// When the run that wrote it started, in nanoseconds since the epoch; zero for a shard not on disk.
    let writtenAt: Int64
    private let map: RawFileMap?
    private(set) var entries: [String: StoredEntry]
    /// Whether the shard must be written: an entry changed, was added or was pruned, or the file was unreadable.
    var isDirty: Bool

    init(
        index: Int, writtenAt: Int64 = 0, map: RawFileMap? = nil, entries: [String: StoredEntry] = [:],
        dirty: Bool = false
    ) {
        self.index = index
        self.writtenAt = writtenAt
        self.map = map
        self.entries = entries
        isDirty = dirty
    }

    /// What reading a shard file gave.
    enum Loaded {
        case shard(Shard)
        /// No file, or one another build wrote: an empty shard, rewritten only if the run adds to it.
        case absent
        /// The file is not a shard this code can read: an empty shard, rewritten, and reported.
        case corrupt
    }

    static func load(path: String, index: Int, identity: CacheIdentity, salt: UInt64) -> Loaded {
        let descriptor = unsafe open(path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return .absent }
        defer { close(descriptor) }
        var status = stat()
        guard unsafe fstat(descriptor, &status) == 0 else { return .corrupt }
        let size = Int(status.st_size)
        guard size > 0, let map = try? RawFileMap(fileDescriptor: descriptor, capacity: size) else { return .corrupt }
        let bytes = unsafe map.region(offset: 0, count: size)
        do throws(WireError) {
            return try unsafe WireReader.withReader(overUnsafeBytes: bytes) { (reader) throws(WireError) -> Loaded in
                try parse(&reader, index: index, map: map, identity: identity, salt: salt)
            }
        } catch {
            return .corrupt
        }
    }

    private static func parse(
        _ reader: inout WireReader, index: Int, map: RawFileMap, identity: CacheIdentity, salt: UInt64
    ) throws(WireError) -> Loaded {
        var tool: String?
        var version: String?
        var build: String?
        var writtenAt: Int64 = 0
        var shardSalt: UInt64 = 0
        var entries: [String: StoredEntry] = [:]
        while let tag = try reader.nextTag() {
            switch (tag.fieldNumber.rawValue, tag.wireType) {
            case (1, .lengthDelimited): tool = try reader.readString()
            case (2, .lengthDelimited): version = try reader.readString()
            case (3, .lengthDelimited): build = try reader.readString()
            case (4, .fixed64): writtenAt = Int64(bitPattern: try reader.readFixed64())
            case (6, .fixed64): shardSalt = try reader.readFixed64()
            case (5, .lengthDelimited):
                // The identity comes first; a shard another build wrote is not read further.
                guard tool == identity.tool, version == identity.version, build == identity.build else {
                    return tool == nil ? .corrupt : .absent
                }
                let (path, entry) = try reader.readMessage { (entry) throws(WireError) in try parseEntry(&entry) }
                entries[path] = entry
            default: try reader.skipField(tag)
            }
        }
        guard tool != nil else { return .corrupt }
        guard tool == identity.tool, version == identity.version, build == identity.build, shardSalt == salt else {
            return .absent
        }
        return .shard(Shard(index: index, writtenAt: writtenAt, map: map, entries: entries))
    }

    private static func parseEntry(_ reader: inout WireReader) throws(WireError) -> (String, StoredEntry) {
        var path = ""
        var key = StatKey(device: 0, inode: 0, size: 0, modified: 0, changed: 0)
        var hash: UInt64 = 0
        var payload: Range<Int> = 0..<0
        while let tag = try reader.nextTag() {
            switch (tag.fieldNumber.rawValue, tag.wireType) {
            case (1, .lengthDelimited): path = try reader.readString()
            case (2, .fixed64): key.device = try reader.readFixed64()
            case (3, .fixed64): key.inode = try reader.readFixed64()
            case (4, .fixed64): key.size = try reader.readFixed64()
            case (5, .fixed64): key.modified = Int64(bitPattern: try reader.readFixed64())
            case (6, .fixed64): key.changed = Int64(bitPattern: try reader.readFixed64())
            case (7, .fixed64): hash = try reader.readFixed64()
            case (8, .lengthDelimited): payload = try reader.readPayloadRange()
            default: try reader.skipField(tag)
            }
        }
        return (path, StoredEntry(stat: key, contentHash: hash, payload: .mapped(payload)))
    }

    /// An entry's payload bytes.
    func payload(of entry: StoredEntry) -> [UInt8] {
        switch entry.payload {
        case .bytes(let bytes): return bytes
        case .mapped(let range):
            guard let map, !range.isEmpty else { return [] }
            return unsafe Array(map.region(offset: range.lowerBound, count: range.count))
        }
    }

    func set(_ path: String, _ entry: StoredEntry) {
        entries[path] = entry
        isDirty = true
    }

    func remove(_ path: String) {
        guard entries.removeValue(forKey: path) != nil else { return }
        isDirty = true
    }

    /// The shard file's bytes, entries sorted by path so equal contents write equal files.
    func encoded(identity: CacheIdentity, salt: UInt64, writtenAt: Int64) -> [UInt8] {
        var writer = WireWriter()
        writer.appendTag(1, .lengthDelimited)
        writer.appendString(identity.tool)
        writer.appendTag(2, .lengthDelimited)
        writer.appendString(identity.version)
        writer.appendTag(3, .lengthDelimited)
        writer.appendString(identity.build)
        writer.appendTag(4, .fixed64)
        writer.appendFixed64(UInt64(bitPattern: writtenAt))
        writer.appendTag(6, .fixed64)
        writer.appendFixed64(salt)
        for path in entries.keys.sorted() {
            guard let entry = entries[path] else { continue }
            let payload = payload(of: entry)
            try? writer.appendMessage(field: 5) { (message) throws(WireError) in
                message.appendTag(1, .lengthDelimited)
                message.appendString(path)
                for (field, value) in [
                    (FieldNumber(2), entry.stat.device), (3, entry.stat.inode), (4, entry.stat.size),
                    (5, UInt64(bitPattern: entry.stat.modified)), (6, UInt64(bitPattern: entry.stat.changed)),
                    (7, entry.contentHash),
                ] {
                    message.appendTag(field, .fixed64)
                    message.appendFixed64(value)
                }
                message.appendTag(8, .lengthDelimited)
                message.appendBytes(payload)
            }
        }
        return writer.bytes
    }
}

/// The shards of one workspace under a cache root, and the root's upkeep: the v1 file and legacy directories it
/// replaces, and the budget (ADR-0011).
enum FactsStore {
    /// Shards per workspace; a file's shard is chosen by its directory.
    static let shardCount = 32
    /// An entry whose file was modified less than this before its shard's run started is re-hashed (git's racy-clean
    /// rule, widened to the coarsest file-system timestamp, one second).
    static let racyWindow: Int64 = 1_000_000_000

    static func workspaceDirectory(_ location: CacheLocation) -> String {
        location.root + "/facts/" + hex(XXH64.hash(Array(SourcePath.canonical(location.workspace).utf8)))
    }

    /// `path` without its last component, as `NSString.deletingLastPathComponent` gives it for an absolute path
    /// (`/a/b.swift` → `/a`, `/b.swift` → `/`), which FoundationEssentials does not have.
    static func parent(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return slash == path.startIndex ? "/" : String(path[..<slash])
    }

    /// Whether `path` is a directory, following a link; FoundationEssentials has no `ObjCBool`.
    static func isDirectory(_ path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: SourcePath.canonical(path)))?[.type] as? FileAttributeType
            == .typeDirectory
    }

    static func shardIndex(of path: String) -> Int {
        let directory = Self.parent(of: path)
        return Int(XXH64.hash(Array(directory.utf8)) % UInt64(shardCount))
    }

    static func shardPath(_ location: CacheLocation, _ index: Int) -> String {
        let name = String(index, radix: 16)
        return workspaceDirectory(location) + "/" + (name.count == 1 ? "0" + name : name) + ".shard"
    }

    static func hex(_ value: UInt64) -> String {
        let digits = String(value, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }

    /// The paths with an entry, in every shard of the workspace.
    static func cachedPaths(at location: CacheLocation, identity: CacheIdentity, salt: UInt64 = 0) -> Set<String> {
        var paths: Set<String> = []
        for index in 0..<shardCount {
            if case .shard(let shard) = Shard.load(
                path: shardPath(location, index), index: index, identity: identity, salt: salt)
            {
                paths.formUnion(shard.entries.keys)
            }
        }
        return paths
    }

    /// Whether `path` holds a regular file whose first line is a v1 cache header (`<tool> facts <version> <build>`).
    static func isVersionOneCache(_ path: String) -> Bool {
        guard let bytes = try? BoundedFileReader.read(path: path, cap: 4096) else { return false }
        let line = bytes.prefix { $0 != 0x0A }
        let words = line.split(separator: 0x20)
        return line.count < bytes.count && words.count == 4 && Array(words[1]) == Array("facts".utf8)
    }

    /// Makes the root a directory and removes what older layouts left: a v1 file at the root itself, and directories
    /// holding nothing but a v1 `facts.json`. Anything else is left alone. Returns why the cache cannot be used, if so.
    static func prepareRoot(_ root: String) -> String? {
        let manager = FileManager.default
        if manager.fileExists(atPath: root), !Self.isDirectory(root) {
            guard isVersionOneCache(root) else {
                return "the cache path \(root) is a file that is not a cache; it was left alone and no cache was used"
            }
            try? manager.removeItem(atPath: root)
        }
        for name in (try? manager.contentsOfDirectory(atPath: root)) ?? [] where name != "facts" && name != "index" {
            let path = root + "/" + name
            if name == "facts.json", isVersionOneCache(path) {
                try? manager.removeItem(atPath: path)
            } else if (try? manager.contentsOfDirectory(atPath: path)) == ["facts.json"],
                isVersionOneCache(path + "/facts.json")
            {
                try? manager.removeItem(atPath: path)
            }
        }
        return nil
    }

    /// Removes the least recently used workspaces and index databases, then the current workspace's oldest shards, until
    /// everything under the root fits `location.maximumBytes`. The current workspace was touched by this run.
    static func enforceBudget(_ location: CacheLocation) {
        var total = size(of: location.root)
        guard total > location.maximumBytes else { return }
        let manager = FileManager.default
        let current = workspaceDirectory(location)
        var candidates: [(path: String, used: Date)] = []
        for parent in [location.root + "/facts", location.root + "/index"] {
            for name in (try? manager.contentsOfDirectory(atPath: parent)) ?? [] {
                let path = parent + "/" + name
                guard path != current else { continue }
                candidates.append((path, modificationDate(path)))
            }
        }
        for candidate in candidates.sorted(by: { $0.used < $1.used }) where total > location.maximumBytes {
            let freed = size(of: candidate.path)
            try? manager.removeItem(atPath: candidate.path)
            total -= freed
        }
        guard total > location.maximumBytes else { return }
        let shards = ((try? manager.contentsOfDirectory(atPath: current)) ?? []).filter { $0.hasSuffix(".shard") }
            .map { current + "/" + $0 }.sorted { modificationDate($0) < modificationDate($1) }
        for shard in shards where total > location.maximumBytes {
            let freed = size(of: shard)
            try? manager.removeItem(atPath: shard)
            total -= freed
        }
    }

    static func modificationDate(_ path: String) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date ?? .distantPast
    }

    /// The bytes of the regular files at or under `path`.
    static func size(of path: String) -> Int {
        let manager = FileManager.default
        guard manager.fileExists(atPath: path) else { return 0 }
        guard Self.isDirectory(path) else { return (try? manager.attributesOfItem(atPath: path))?[.size] as? Int ?? 0 }
        return regularBytes(under: path)
    }

    /// The bytes of the regular files under the directory `path`, links not followed. A walk by hand:
    /// FoundationEssentials has no `subpaths(atPath:)`.
    private static func regularBytes(under path: String) -> Int {
        let manager = FileManager.default
        var total = 0
        for name in (try? manager.contentsOfDirectory(atPath: path)) ?? [] {
            let child = path + "/" + name
            let attributes = (try? manager.attributesOfItem(atPath: child)) ?? [:]
            switch attributes[.type] as? FileAttributeType {
            case .typeRegular?: total += attributes[.size] as? Int ?? 0
            case .typeDirectory?: total += regularBytes(under: child)
            default: break
            }
        }
        return total
    }
}
