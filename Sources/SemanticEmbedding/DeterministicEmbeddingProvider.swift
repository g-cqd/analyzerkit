/// A deterministic, dependency-free provider: it hashes character n-grams (FNV-1a 64 over Unicode scalars) into
/// bucketed counts. It is not semantically meaningful (code that differs by renamed identifiers lands in other
/// buckets) but it is total, stable and cheap, so shape-similar snippets still cluster. It is the fallback when the
/// on-device asset is missing and the oracle for tests.
public struct DeterministicEmbeddingProvider: SemanticEmbeddingProvider {
    public let embeddingDimension: Int
    public let ngramSize: Int
    public let providerName: String

    public init(
        dimension: Int = 128,
        ngramSize: Int = 3,
        providerName: String = "deterministic (n-gram hash, fallback)"
    ) {
        precondition(dimension > 0, "dimension must be > 0")
        precondition(ngramSize > 0, "ngramSize must be > 0")
        self.embeddingDimension = dimension
        self.ngramSize = ngramSize
        self.providerName = providerName
    }

    public func embed(snippet: String) async throws -> [Float] {
        var buckets = [Float](repeating: 0, count: embeddingDimension)
        let scalars = Array(snippet.unicodeScalars)
        guard scalars.count >= ngramSize else { return buckets }
        for start in 0...(scalars.count - ngramSize) {
            var hash: UInt64 = 0xCBF2_9CE4_8422_2325  // FNV-1a offset basis
            for offset in 0..<ngramSize {
                hash ^= UInt64(scalars[start + offset].value)
                hash = hash &* 0x0000_0100_0000_01B3  // FNV-1a prime
            }
            buckets[Int(hash % UInt64(embeddingDimension))] += 1
        }
        return buckets
    }
}
