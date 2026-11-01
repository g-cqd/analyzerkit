import SemanticEmbedding
import Testing

#if canImport(NaturalLanguage)
    @Suite struct OnDeviceProviderTests {
        /// The system asset may be absent (offline, CI): the provider then throws at construction, which is its contract,
        /// and the fallback is the deterministic one. Either way the provider handed out embeds to its stated dimension.
        @Test func `the on-device provider embeds to its dimension, or the fallback does`() async throws {
            let provider = SemanticEmbeddingProviders.onDeviceOrFallback()
            let vector = try await provider.embed(snippet: "func add(_ a: Int, _ b: Int) -> Int { a + b }")
            #expect(vector.count == provider.embeddingDimension)
            #expect(vector.contains { $0 != 0 })
            #expect(!provider.providerName.isEmpty)
        }

        @Test func `a missing asset is a load failure that names the cause`() {
            let error = SemanticEmbeddingError.modelLoadFailed(underlying: NLContextualEmbeddingError.assetsUnavailable)
            #expect(error.description.contains("assets are not available"))
        }
    }
#endif
