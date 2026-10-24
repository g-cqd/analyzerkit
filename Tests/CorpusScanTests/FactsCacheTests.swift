import CorpusScan
import Foundation
import SourceCorpus
import Testing

struct SampleFacts: Codable, Sendable, Equatable { var names: [String] }

@Suite struct FactsCacheTests {
    typealias Cache = FactsCache<SampleFacts>

    private func identity(_ build: String = "build-a") -> Cache.Identity {
        Cache.Identity(tool: "sample", version: "1.0", build: build)
    }

    @Test func `a hit needs the same path and the same fingerprint`() {
        var cache = Cache()
        cache.update(path: "/x/A.swift", fingerprint: "fp", facts: SampleFacts(names: ["A"]))
        #expect(cache.facts(for: "/x/A.swift", fingerprint: "fp") == SampleFacts(names: ["A"]))
        #expect(cache.facts(for: "/x/A.swift", fingerprint: "other") == nil)
        #expect(cache.facts(for: "/x/B.swift", fingerprint: "fp") == nil)
    }

    @Test func `a cache is read back only by the build that wrote it`() throws {
        try Scratch.with { scratch in
            var cache = Cache()
            cache.update(path: "/x/A.swift", fingerprint: "fp", facts: SampleFacts(names: ["A", "é"]))
            let url = scratch.root.appending(path: "nested/facts.json")

            cache.persist(url: url, identity: identity())
            let reloaded = Cache.load(url: url, identity: identity())
            #expect(reloaded.facts(for: "/x/A.swift", fingerprint: "fp") == SampleFacts(names: ["A", "é"]))
            #expect(Cache.load(url: url, identity: identity("build-b")).entries.isEmpty)
            #expect(Cache.load(url: url, identity: nil).entries.isEmpty)
        }
    }

    @Test func `a build with no identity writes nothing`() throws {
        try Scratch.with { scratch in
            let url = scratch.root.appending(path: "facts.json")
            Cache(entries: ["/x": .init(fingerprint: "f", facts: SampleFacts(names: []))]).persist(
                url: url, identity: nil)
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func `a corrupt payload under this build's header fails open and says why`() throws {
        try Scratch.with { scratch in
            let url = scratch.root.appending(path: "facts.json")
            try Data("sample facts 1.0 build-a\n{not json".utf8).write(to: url)
            let cache = Cache.load(url: url, identity: identity())
            #expect(cache.entries.isEmpty)
            #expect(cache.loadFailure?.contains("could not be decoded") == true)
        }
    }

    @Test func `a foreign file is an ordinary miss with no failure`() throws {
        try Scratch.with { scratch in
            let url = scratch.root.appending(path: "facts.json")
            try Data("{\"entries\":{}}".utf8).write(to: url)
            let cache = Cache.load(url: url, identity: identity())
            #expect(cache.entries.isEmpty)
            #expect(cache.loadFailure == nil)
        }
    }

    @Test func `a missing file is an empty cache`() throws {
        try Scratch.with { scratch in
            let cache = Cache.load(url: scratch.root.appending(path: "none.json"), identity: identity())
            #expect(cache.entries.isEmpty && cache.loadFailure == nil)
        }
    }
}
