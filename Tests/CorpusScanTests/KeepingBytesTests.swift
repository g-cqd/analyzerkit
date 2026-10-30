import CorpusScan
import Foundation
import SourceCorpus
import Testing

/// `keepingBytes` (roadmap 0020): a tool that needs every file's text after the scan (dolly rebuilds its tokens from the
/// cached payload and the source, and embeds snippets of it) gets the bytes the scan read, on a hit as on a miss, instead
/// of reading every file a second time.
@Suite struct KeepingBytesTests {
    @Test func `every file comes back with its bytes, hit or miss, stat key or not`() async throws {
        try await Scratch.withAsync { scratch in
            let h = Harness(scratch: scratch)
            let a = try h.settled("A.swift", "a1\na2")
            let b = try scratch.write("B.swift", "b1")
            let missing = scratch.path("Missing.swift")
            for run in 0..<2 {
                let result = try await CorpusScanner.scan(
                    paths: [a, b, missing], cache: h.location(), identity: h.identity, keepingBytes: true
                ) { _, bytes in SampleFacts(names: [String(decoding: bytes, as: UTF8.self)]) }
                let byName = Dictionary(uniqueKeysWithValues: result.files.map { ($0.path, $0) })
                #expect(byName[SourcePath.canonical(a)]?.bytes == Array("a1\na2".utf8), "run \(run)")
                #expect(byName[SourcePath.canonical(b)]?.bytes == Array("b1".utf8), "run \(run)")
                #expect(byName[SourcePath.canonical(missing)]?.bytes == nil)
                if run == 1 { #expect(result.cacheHits == 2) }
            }
        }
    }

    @Test func `without it no bytes are kept, and a settled hit reads nothing`() async throws {
        try await Scratch.withAsync { scratch in
            let h = Harness(scratch: scratch)
            let a = try h.settled("A.swift", "a1")
            _ = try await h.scan([a], cache: h.location())
            let warm = try await h.scan([a], cache: h.location())
            #expect(warm.files.first?.bytes == nil)
            #expect(warm.filesRead == 0)
        }
    }
}
