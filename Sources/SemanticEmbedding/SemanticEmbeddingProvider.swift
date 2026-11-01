//  The embedding providers arcleak, deadwood and dolly each carried a copy of (roadmap 0028), lifted from
//  SwiftStaticAnalysis (MIT), DuplicationDetector/Semantic.

/// A source of fixed-dimension embeddings for code snippets.
///
/// Three conformers ship. ``DeterministicEmbeddingProvider`` needs nothing and never fails: the test oracle and the
/// fallback. `NLContextualSemanticEmbeddingProvider` is Apple's on-device `NLContextualEmbedding` (no download, not trained
/// on code). `HFSemanticEmbeddingProvider` is a Core ML model with its HuggingFace tokenizer, which the user supplies
/// (`--embedding-bundle`) and which is worth it because a code-trained model groups tighter than an English one.
public protocol SemanticEmbeddingProvider: Sendable {
    /// Dimension of every embedding this provider returns. Callers validate dimension equality before comparing.
    var embeddingDimension: Int { get }

    /// The model that actually ran, for the stderr note and for annotated findings: a run falls back across providers,
    /// and which one produced a score changes how to read it.
    var providerName: String { get }

    /// Embeds a code snippet into a dense vector.
    func embed(snippet: String) async throws -> [Float]

    /// Embeds several snippets. The default runs ``embed(snippet:)`` one at a time, in order.
    func embed(snippets: [String]) async throws -> [[Float]]
}

extension SemanticEmbeddingProvider {
    public var providerName: String { "embedding" }

    public func embed(snippets: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        results.reserveCapacity(snippets.count)
        for snippet in snippets {
            results.append(try await embed(snippet: snippet))
        }
        return results
    }
}

/// Why a provider could not be built or could not embed.
public enum SemanticEmbeddingError: Error, Sendable, CustomStringConvertible {
    case modelLoadFailed(underlying: any Error)
    case inferenceFailed(reason: String)

    public var description: String {
        switch self {
        case .modelLoadFailed(let underlying):
            "failed to load embedding model: \(underlying)"
        case .inferenceFailed(let reason):
            "embedding inference failed: \(reason)"
        }
    }
}
