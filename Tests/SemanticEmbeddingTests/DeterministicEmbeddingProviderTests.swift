import Foundation
import SemanticEmbedding
import Testing

@Suite struct DeterministicEmbeddingProviderTests {
    /// The three copies this provider replaced (arcleak's, deadwood's, dolly's) hashed each scalar n-gram with FNV-1a 64
    /// into `hash % dimension`; this recomputes that from the constants so the shared one cannot drift from them.
    private func reference(_ text: String, dimension: Int, ngram: Int) -> [Float] {
        var buckets = [Float](repeating: 0, count: dimension)
        let scalars = Array(text.unicodeScalars)
        guard scalars.count >= ngram else { return buckets }
        for start in 0...(scalars.count - ngram) {
            var hash: UInt64 = 14_695_981_039_346_656_037
            for offset in 0..<ngram {
                hash ^= UInt64(scalars[start + offset].value)
                hash = hash &* 1_099_511_628_211
            }
            buckets[Int(hash % UInt64(dimension))] += 1
        }
        return buckets
    }

    @Test(arguments: [
        ("", 16, 3), ("ab", 16, 3), ("abcabcabc", 8, 3), ("func f() -> Int { 1 }", 128, 3), ("héllo 🙂 wörld", 32, 2),
    ])
    func `the vectors are the n-gram hash buckets the tools' copies produced`(
        _ text: String,
        _ dimension: Int,
        _ ngram: Int
    )
        async throws
    {
        let provider = DeterministicEmbeddingProvider(dimension: dimension, ngramSize: ngram)
        #expect(try await provider.embed(snippet: text) == reference(text, dimension: dimension, ngram: ngram))
        #expect(provider.embeddingDimension == dimension)
    }

    @Test func `the defaults are 128 buckets of trigrams, and the name says it is the fallback`() async throws {
        let provider = DeterministicEmbeddingProvider()
        #expect(provider.embeddingDimension == 128)
        #expect(provider.ngramSize == 3)
        #expect(provider.providerName == "deterministic (n-gram hash, fallback)")
        #expect(DeterministicEmbeddingProvider(providerName: "deterministic (CI)").providerName == "deterministic (CI)")
    }

    @Test func `a batch is the snippets one by one, in order`() async throws {
        let provider = DeterministicEmbeddingProvider(dimension: 16)
        let snippets = ["alpha", "beta", "", "gamma gamma"]
        let batch = try await provider.embed(snippets: snippets)
        var single: [[Float]] = []
        for snippet in snippets { single.append(try await provider.embed(snippet: snippet)) }
        #expect(batch == single)
    }

    @Test func `the failures describe themselves`() {
        struct Boom: Error {}
        #expect(SemanticEmbeddingError.inferenceFailed(reason: "shape").description.contains("shape"))
        #expect(SemanticEmbeddingError.modelLoadFailed(underlying: Boom()).description.contains("Boom"))
    }
}
