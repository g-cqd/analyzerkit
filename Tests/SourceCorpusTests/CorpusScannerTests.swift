import Foundation
import SourceCorpus
import Synchronization
import Testing

/// Counts extractions across the scan's concurrent tasks.
final class Counter: Sendable {
    private let storage = Mutex(0)
    func increment() { storage.withLock { $0 += 1 } }
    var value: Int { storage.withLock { $0 } }
}

@Suite struct CorpusScannerTests {
    typealias Cache = FactsCache<SampleFacts>

    private let identity = Cache.Identity(tool: "sample", version: "1.0", build: "b")

    /// Facts are the file's lines; the counter records how many extractions really ran.
    private func scan(
        _ paths: [String], cacheURL: URL? = nil, salt: String = "", extractions: Counter? = nil
    ) async throws -> CorpusScan<SampleFacts> {
        try await CorpusScanner.scan(paths: paths, cacheURL: cacheURL, identity: identity, salt: salt) { _, bytes in
            extractions?.increment()
            return SampleFacts(names: String(decoding: bytes, as: UTF8.self).split(separator: "\n").map(String.init))
        }
    }

    @Test func `every file is extracted once, sorted by path, with its facts`() async throws {
        try await Scratch.withAsync { scratch in
            let b = try scratch.write("B.swift", "b1\nb2")
            let a = try scratch.write("A.swift", "a1")
            let result = try await scan([b, a])
            #expect(result.files.map(\.path) == [SourcePath.canonical(a), SourcePath.canonical(b)])
            #expect(result.files.map(\.facts) == [SampleFacts(names: ["a1"]), SampleFacts(names: ["b1", "b2"])])
            #expect(result.cacheHits == 0 && result.cacheMisses == 2)
        }
    }

    @Test func `one file named in two spellings is extracted once`() async throws {
        try await Scratch.withAsync { scratch in
            let a = try scratch.write("dir/A.swift")
            let extractions = Counter()
            let result = try await scan([a, scratch.path("dir/./A.swift")], extractions: extractions)
            #expect(result.files.count == 1)
            #expect(extractions.value == 1)
        }
    }

    @Test func `an unreadable file is reported degraded and the others still scan`() async throws {
        try await Scratch.withAsync { scratch in
            let good = try scratch.write("Good.swift")
            let result = try await scan([good, scratch.path("Missing.swift")])
            let missing = try #require(result.files.first { $0.path.hasSuffix("Missing.swift") })
            #expect(missing.facts == nil && missing.failure != nil)
            #expect(result.files.first { $0.path.hasSuffix("Good.swift") }?.facts != nil)
        }
    }

    @Test func `a second run over unchanged files extracts nothing`() async throws {
        try await Scratch.withAsync { scratch in
            let paths = [try scratch.write("A.swift", "a"), try scratch.write("B.swift", "b")]
            let cacheURL = scratch.root.appending(path: "cache/facts.json")
            _ = try await scan(paths, cacheURL: cacheURL)

            let extractions = Counter()
            let warm = try await scan(paths, cacheURL: cacheURL, extractions: extractions)
            #expect(extractions.value == 0)
            #expect(warm.cacheHits == 2 && warm.cacheMisses == 0)
            #expect(warm.files.map(\.facts) == [SampleFacts(names: ["a"]), SampleFacts(names: ["b"])])
        }
    }

    @Test func `a changed file, and only that file, is extracted again`() async throws {
        try await Scratch.withAsync { scratch in
            let a = try scratch.write("A.swift", "a")
            let b = try scratch.write("B.swift", "b")
            let cacheURL = scratch.root.appending(path: "facts.json")
            _ = try await scan([a, b], cacheURL: cacheURL)
            try scratch.write("B.swift", "changed")

            let extractions = Counter()
            let result = try await scan([a, b], cacheURL: cacheURL, extractions: extractions)
            #expect(extractions.value == 1)
            #expect(result.files.last?.facts == SampleFacts(names: ["changed"]))
        }
    }

    @Test func `a different salt invalidates every entry`() async throws {
        try await Scratch.withAsync { scratch in
            let a = try scratch.write("A.swift", "a")
            let cacheURL = scratch.root.appending(path: "facts.json")
            _ = try await scan([a], cacheURL: cacheURL, salt: "DEBUG")
            let extractions = Counter()
            _ = try await scan([a], cacheURL: cacheURL, salt: "RELEASE", extractions: extractions)
            #expect(extractions.value == 1)
        }
    }

    @Test func `a run over part of the corpus keeps the other entries and prunes deleted files`() async throws {
        try await Scratch.withAsync { scratch in
            let a = try scratch.write("A.swift", "a")
            let b = try scratch.write("B.swift", "b")
            let gone = try scratch.write("Gone.swift", "g")
            let cacheURL = scratch.root.appending(path: "facts.json")
            _ = try await scan([a, b, gone], cacheURL: cacheURL)
            try FileManager.default.removeItem(atPath: gone)

            _ = try await scan([a], cacheURL: cacheURL)
            let kept = Cache.load(url: cacheURL, identity: identity)
            #expect(Set(kept.entries.keys) == [SourcePath.canonical(a), SourcePath.canonical(b)])
        }
    }

    @Test func `a cache that fails to decode is reported once and then replaced`() async throws {
        try await Scratch.withAsync { scratch in
            let a = try scratch.write("A.swift", "a")
            let cacheURL = scratch.root.appending(path: "facts.json")
            try Data("sample facts 1.0 b\n{broken".utf8).write(to: cacheURL)

            let first = try await scan([a], cacheURL: cacheURL)
            #expect(first.cacheLoadFailure != nil)
            let second = try await scan([a], cacheURL: cacheURL)
            #expect(second.cacheLoadFailure == nil && second.cacheHits == 1)
        }
    }

    @Test func `a cancelled scan throws and leaves the cache alone`() async throws {
        try await Scratch.withAsync { scratch in
            let paths = try (0..<20).map { try scratch.write("F\($0).swift", "x\($0)") }
            let cacheURL = scratch.root.appending(path: "facts.json")
            let task = Task { try await scan(paths, cacheURL: cacheURL) }
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(!FileManager.default.fileExists(atPath: cacheURL.path))
        }
    }

    @Test func `width one still scans the whole corpus`() async throws {
        try await Scratch.withAsync { scratch in
            let paths = try (0..<10).map { try scratch.write("F\($0).swift", "x") }
            let result = try await CorpusScanner.scan(paths: paths, identity: identity, width: 1) { _, _ in
                SampleFacts(names: [])
            }
            #expect(result.files.count == 10)
        }
    }
}
