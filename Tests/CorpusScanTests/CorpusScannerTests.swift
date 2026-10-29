import CorpusScan
import Foundation
import SourceCorpus
import Synchronization
import Testing

@testable import CorpusScan

struct SampleFacts: Codable, Sendable, Equatable { var names: [String] }

/// Counts extractions across the scan's concurrent tasks.
final class Counter: Sendable {
    private let storage = Mutex(0)
    func increment() { storage.withLock { $0 += 1 } }
    var value: Int { storage.withLock { $0 } }
}

/// What every scan in these tests uses: facts are the file's lines.
struct Harness {
    let scratch: Scratch
    var identity: CacheIdentity? = CacheIdentity(tool: "sample", version: "1.0", build: "b")

    func location(workspace: String = "ws", maximumBytes: Int = CacheLocation.defaultMaximumBytes) -> CacheLocation {
        CacheLocation(root: scratch.path("cache"), workspace: scratch.path(workspace), maximumBytes: maximumBytes)
    }

    func scan(
        _ paths: [String], cache: CacheLocation? = nil, salt: String = "", extractions: Counter? = nil
    ) async throws -> CorpusScan<SampleFacts> {
        try await CorpusScanner.scan(paths: paths, cache: cache, identity: identity, salt: salt) { _, bytes in
            extractions?.increment()
            return SampleFacts(names: String(decoding: bytes, as: UTF8.self).split(separator: "\n").map(String.init))
        }
    }

    /// Writes `path` and dates it an hour back, so the racy-clean rule does not apply to it.
    @discardableResult
    func settled(_ path: String, _ contents: String) throws -> String {
        let file = try scratch.write(path, contents)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: file)
        return file
    }

    /// Every shard file under the cache root, with what tells a rewrite: its inode and modification time.
    func shards() -> [String: String] {
        let root = scratch.path("cache")
        var shards: [String: String] = [:]
        for path in FileManager.default.subpaths(atPath: root) ?? [] where path.hasSuffix(".shard") {
            let attributes = (try? FileManager.default.attributesOfItem(atPath: root + "/" + path)) ?? [:]
            shards[path] = "\(attributes[.systemFileNumber] ?? 0) \(attributes[.modificationDate] ?? 0)"
        }
        return shards
    }
}

@Suite struct CorpusScannerTests {
    @Test func `every file is extracted once, sorted by path, with its facts`() async throws {
        try await Scratch.withAsync { scratch in
            let h = Harness(scratch: scratch)
            let b = try scratch.write("B.swift", "b1\nb2")
            let a = try scratch.write("A.swift", "a1")
            let result = try await h.scan([b, a])
            #expect(result.files.map(\.path) == [SourcePath.canonical(a), SourcePath.canonical(b)])
            #expect(result.files.map(\.facts) == [SampleFacts(names: ["a1"]), SampleFacts(names: ["b1", "b2"])])
            #expect(result.cacheHits == 0 && result.cacheMisses == 2)
        }
    }

    @Test func `one file named in two spellings is extracted once`() async throws {
        try await Scratch.withAsync { scratch in
            let a = try scratch.write("dir/A.swift")
            let extractions = Counter()
            let result = try await Harness(scratch: scratch).scan(
                [a, scratch.path("dir/./A.swift")], extractions: extractions)
            #expect(result.files.count == 1)
            #expect(extractions.value == 1)
        }
    }

    @Test func `an unreadable file is reported degraded and the others still scan`() async throws {
        try await Scratch.withAsync { scratch in
            let good = try scratch.write("Good.swift")
            let result = try await Harness(scratch: scratch).scan([good, scratch.path("Missing.swift")])
            let missing = try #require(result.files.first { $0.path.hasSuffix("Missing.swift") })
            #expect(missing.facts == nil && missing.failure != nil)
            #expect(result.files.first { $0.path.hasSuffix("Good.swift") }?.facts != nil)
        }
    }

    /// ADR-0011 item 2: the stat key decides, and no source file is opened.
    @Test func `a warm run opens no source file whose stat key matches`() async throws {
        try await Scratch.withAsync { scratch in
            let h = Harness(scratch: scratch)
            let paths = try (0..<20).map { try h.settled("Dir\($0 % 4)/F\($0).swift", "f\($0)") }
            let cold = try await h.scan(paths, cache: h.location())
            #expect(cold.filesRead == 20 && cold.cacheHits == 0)
            let extractions = Counter()
            let warm = try await h.scan(paths, cache: h.location(), extractions: extractions)
            #expect(warm.filesRead == 0)
            #expect(warm.cacheHits == 20 && extractions.value == 0)
            #expect(warm.files.map(\.facts) == cold.files.map(\.facts))
        }
    }

    /// git's racy-clean rule: a file modified around the time its entry was written may change again within the same
    /// timestamp, so its stat key is not trusted; its content hash still saves the extraction.
    @Test func `a file modified as the cache was written is re-read, and its hash still hits`() async throws {
        try await Scratch.withAsync { scratch in
            let h = Harness(scratch: scratch)
            let fresh = try scratch.write("Fresh.swift", "fresh")
            let old = try h.settled("Old.swift", "old")
            _ = try await h.scan([fresh, old], cache: h.location())
            let extractions = Counter()
            let warm = try await h.scan([fresh, old], cache: h.location(), extractions: extractions)
            #expect(warm.filesRead == 1)
            #expect(warm.cacheHits == 2 && extractions.value == 0)
        }
    }

    @Test func `an edit that keeps the size and the modification time is still seen`() async throws {
        try await Scratch.withAsync { scratch in
            let h = Harness(scratch: scratch)
            let file = try h.settled("A.swift", "aaaa")
            let modified = try #require(
                try FileManager.default.attributesOfItem(atPath: file)[.modificationDate] as? Date)
            _ = try await h.scan([file], cache: h.location())
            try scratch.write("A.swift", "bbbb")
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file)
            let result = try await h.scan([file], cache: h.location())
            #expect(result.files.first?.facts == SampleFacts(names: ["bbbb"]))
        }
    }

    @Test func `a changed file, and only that file, is extracted again`() async throws {
        try await Scratch.withAsync { scratch in
            let h = Harness(scratch: scratch)
            let a = try h.settled("A.swift", "a")
            let b = try h.settled("B.swift", "b")
            _ = try await h.scan([a, b], cache: h.location())
            try h.settled("B.swift", "changed")
            let extractions = Counter()
            let result = try await h.scan([a, b], cache: h.location(), extractions: extractions)
            #expect(extractions.value == 1)
            #expect(result.files.last?.facts == SampleFacts(names: ["changed"]))
        }
    }

    /// ADR-0011 item 3: a run rewrites only the shards it changed.
    @Test func `only the shard of a changed file is rewritten, and none when nothing changed`() async throws {
        try await Scratch.withAsync { scratch in
            let h = Harness(scratch: scratch)
            let paths = try (0..<30).map { try h.settled("Module\($0 % 6)/F\($0).swift", "f\($0)") }
            _ = try await h.scan(paths, cache: h.location())
            let first = h.shards()
            #expect(first.count > 1)
            _ = try await h.scan(paths, cache: h.location())
            #expect(h.shards() == first)
            try h.settled("Module2/F2.swift", "edited")
            _ = try await h.scan(paths, cache: h.location())
            let changed = h.shards().filter { first[$0.key] != $0.value }
            #expect(changed.count == 1, "\(changed.keys)")
        }
    }

    @Test func `a different salt invalidates every entry`() async throws {
        try await Scratch.withAsync { scratch in
            let h = Harness(scratch: scratch)
            let a = try h.settled("A.swift", "a")
            _ = try await h.scan([a], cache: h.location(), salt: "DEBUG")
            let extractions = Counter()
            _ = try await h.scan([a], cache: h.location(), salt: "RELEASE", extractions: extractions)
            #expect(extractions.value == 1)
        }
    }

    @Test func `a cache another build wrote is an ordinary miss, and is replaced`() async throws {
        try await Scratch.withAsync { scratch in
            var h = Harness(scratch: scratch)
            let a = try h.settled("A.swift", "a")
            _ = try await h.scan([a], cache: h.location())
            h.identity = CacheIdentity(tool: "sample", version: "1.0", build: "other")
            let other = try await h.scan([a], cache: h.location())
            #expect(other.cacheHits == 0 && other.cacheLoadFailure == nil)
            let again = try await h.scan([a], cache: h.location())
            #expect(again.cacheHits == 1)
        }
    }

    @Test func `a build with no identity reads and writes no cache`() async throws {
        try await Scratch.withAsync { scratch in
            var h = Harness(scratch: scratch)
            h.identity = nil
            _ = try await h.scan([try h.settled("A.swift", "a")], cache: h.location())
            #expect(!FileManager.default.fileExists(atPath: scratch.path("cache")))
        }
    }

    @Test func `a run over part of the corpus keeps the other entries and prunes deleted files`() async throws {
        try await Scratch.withAsync { scratch in
            let h = Harness(scratch: scratch)
            let a = try h.settled("A.swift", "a")
            let b = try h.settled("B.swift", "b")
            let gone = try h.settled("Gone.swift", "g")
            _ = try await h.scan([a, b, gone], cache: h.location())
            try FileManager.default.removeItem(atPath: gone)
            try h.settled("A.swift", "a2")
            _ = try await h.scan([a], cache: h.location())
            let identity = try #require(h.identity)
            let kept = FactsStore.cachedPaths(at: h.location(), identity: identity)
            #expect(kept == [SourcePath.canonical(a), SourcePath.canonical(b)])
        }
    }

    /// ADR-0011: a corrupt shard is a miss, never a trap; it is reported once and replaced.
    @Test func `a corrupt shard is a miss, reported once, then replaced`() async throws {
        try await Scratch.withAsync { scratch in
            let h = Harness(scratch: scratch)
            let paths = try (0..<10).map { try h.settled("M\($0 % 3)/F\($0).swift", "f\($0)") }
            _ = try await h.scan(paths, cache: h.location())
            for shard in h.shards().keys {
                try Data([0x0A, 0xFF, 0xFF, 0xFF, 0x7F, 1, 2, 3]).write(
                    to: URL(fileURLWithPath: scratch.path("cache/" + shard)))
            }
            let first = try await h.scan(paths, cache: h.location())
            #expect(first.cacheHits == 0)
            #expect(first.cacheLoadFailure != nil)
            #expect(first.files.allSatisfy { $0.facts != nil })
            let second = try await h.scan(paths, cache: h.location())
            #expect(second.cacheLoadFailure == nil && second.cacheHits == 10)
        }
    }

    @Test func `a cancelled scan throws and leaves the cache alone`() async throws {
        try await Scratch.withAsync { scratch in
            let h = Harness(scratch: scratch)
            let paths = try (0..<20).map { try scratch.write("F\($0).swift", "x\($0)") }
            let location = h.location()
            let task = Task { try await h.scan(paths, cache: location) }
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(!FileManager.default.fileExists(atPath: scratch.path("cache")))
        }
    }

    @Test func `width one still scans the whole corpus`() async throws {
        try await Scratch.withAsync { scratch in
            let paths = try (0..<10).map { try scratch.write("F\($0).swift", "x") }
            let result = try await CorpusScanner.scan(paths: paths, width: 1) { _, _ in SampleFacts(names: []) }
            #expect(result.files.count == 10)
        }
    }
}

/// ADR-0011 items 1 and 4: the cache root, its budget, and what is left of older layouts.
@Suite struct CacheRootTests {
    private func size(of directory: String) -> Int {
        var total = 0
        for path in FileManager.default.subpaths(atPath: directory) ?? [] {
            let attributes = (try? FileManager.default.attributesOfItem(atPath: directory + "/" + path)) ?? [:]
            if (attributes[.type] as? FileAttributeType) == .typeRegular { total += (attributes[.size] as? Int) ?? 0 }
        }
        return total
    }

    private func workspaces(_ scratch: Scratch) -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: scratch.path("cache/facts")).count) ?? 0
    }

    @Test func `over its budget, the least recently used workspace goes first`() async throws {
        try await Scratch.withAsync { scratch in
            let h = Harness(scratch: scratch)
            func corpus(_ name: String) throws -> [String] {
                try (0..<12).map { try h.settled("\(name)/D\($0 % 3)/F\($0).swift", "\(name)\($0) and some text") }
            }
            let a = try corpus("A")
            let b = try corpus("B")
            let c = try corpus("C")
            _ = try await h.scan(a, cache: h.location(workspace: "A"))
            let one = size(of: scratch.path("cache"))
            let budget = one * 2 + one / 2
            _ = try await h.scan(b, cache: h.location(workspace: "B", maximumBytes: budget))
            _ = try await h.scan(a, cache: h.location(workspace: "A", maximumBytes: budget))
            _ = try await h.scan(c, cache: h.location(workspace: "C", maximumBytes: budget))
            #expect(workspaces(scratch) == 2)
            #expect(size(of: scratch.path("cache")) <= budget)
            let warmA = try await h.scan(a, cache: h.location(workspace: "A", maximumBytes: budget))
            #expect(warmA.cacheHits == 12, "A was used after B, so B went")
        }
    }

    @Test func `a budget smaller than one workspace is still held`() async throws {
        try await Scratch.withAsync { scratch in
            let h = Harness(scratch: scratch)
            let paths = try (0..<30).map {
                try h.settled("D\($0 % 6)/F\($0).swift", String(repeating: "x", count: 200))
            }
            let result = try await h.scan(paths, cache: h.location(maximumBytes: 2_048))
            #expect(result.files.allSatisfy { $0.facts != nil })
            #expect(size(of: scratch.path("cache")) <= 2_048)
        }
    }

    @Test func `a v1 cache file at the cache path is replaced by the cache directory`() async throws {
        try await Scratch.withAsync { scratch in
            let h = Harness(scratch: scratch)
            try Data("sample facts 1.0 b\n{\"entries\":{}}".utf8).write(to: URL(fileURLWithPath: scratch.path("cache")))
            let a = try h.settled("A.swift", "a")
            _ = try await h.scan([a], cache: h.location())
            var isDirectory: ObjCBool = false
            #expect(unsafe FileManager.default.fileExists(atPath: scratch.path("cache"), isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
            #expect(try await h.scan([a], cache: h.location()).cacheHits == 1)
        }
    }

    @Test func `a file at the cache path that is not a cache is left alone, and no cache is used`() async throws {
        try await Scratch.withAsync { scratch in
            let h = Harness(scratch: scratch)
            try Data("my notes\n".utf8).write(to: URL(fileURLWithPath: scratch.path("cache")))
            let result = try await h.scan([try h.settled("A.swift", "a")], cache: h.location())
            #expect(result.cacheLoadFailure?.contains("not a cache") == true)
            #expect(try String(contentsOfFile: scratch.path("cache"), encoding: .utf8) == "my notes\n")
        }
    }

    @Test func `old per-workspace facts files are removed, and nothing else is`() async throws {
        try await Scratch.withAsync { scratch in
            let h = Harness(scratch: scratch)
            try scratch.write("cache/0123abcd/facts.json", "sample facts 0.9 old\n{}")
            try scratch.write("cache/notes/facts.json", "{\"mine\": true}")
            try scratch.write("cache/README.txt", "keep me")
            _ = try await h.scan([try h.settled("A.swift", "a")], cache: h.location())
            #expect(!FileManager.default.fileExists(atPath: scratch.path("cache/0123abcd")))
            #expect(FileManager.default.fileExists(atPath: scratch.path("cache/notes/facts.json")))
            #expect(FileManager.default.fileExists(atPath: scratch.path("cache/README.txt")))
        }
    }

    @Test func `the default root is the user cache directory of the tool`() {
        #if os(macOS)
            #expect(
                CacheLocation.defaultRoot(tool: "deadwood", environment: [:], home: "/Users/x")
                    == "/Users/x/Library/Caches/deadwood")
        #else
            #expect(
                CacheLocation.defaultRoot(tool: "deadwood", environment: [:], home: "/home/x")
                    == "/home/x/.cache/deadwood")
            #expect(
                CacheLocation.defaultRoot(tool: "deadwood", environment: ["XDG_CACHE_HOME": "/xdg"], home: "/home/x")
                    == "/xdg/deadwood")
        #endif
    }
}
