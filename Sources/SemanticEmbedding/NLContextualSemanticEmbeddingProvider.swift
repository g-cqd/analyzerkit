#if canImport(NaturalLanguage)
    public import NaturalLanguage

    /// A provider backed by Apple's `NLContextualEmbedding`: dense, contextual, sentence-level vectors with no model to
    /// ship, since the English contextual-embedding asset is the system's. Token vectors are mean-pooled to one vector per
    /// snippet.
    ///
    /// It is an English model, not trained on code. It recovers renames and comment edits and part of the structural
    /// clones, but a code-trained bundle (`HFSemanticEmbeddingProvider`) has materially higher recall. If the asset is
    /// not present and cannot be loaded (offline, sandbox), `init` throws and the caller falls back.
    public struct NLContextualSemanticEmbeddingProvider: SemanticEmbeddingProvider {
        public let embeddingDimension: Int
        /// The language the contextual embedding was trained on.
        public let language: NLLanguage

        public var providerName: String { "NLContextualEmbedding (on-device, zero-download)" }

        /// Loads the asset eagerly so a failure of ``embed(snippet:)`` later is not a surprise at construction time.
        public init(language: NLLanguage = .english) throws {
            guard let probe = NLContextualEmbedding(language: language) else {
                throw SemanticEmbeddingError.modelLoadFailed(
                    underlying: NLContextualEmbeddingError.unsupportedLanguage(language)
                )
            }
            guard probe.hasAvailableAssets else {
                throw SemanticEmbeddingError.modelLoadFailed(underlying: NLContextualEmbeddingError.assetsUnavailable)
            }
            do {
                try probe.load()
            } catch {
                throw SemanticEmbeddingError.modelLoadFailed(underlying: error)
            }
            self.embeddingDimension = probe.dimension
            self.language = language
        }

        public func embed(snippet: String) async throws -> [Float] {
            guard let embedding = NLContextualEmbedding(language: language) else {
                throw SemanticEmbeddingError.modelLoadFailed(
                    underlying: NLContextualEmbeddingError.unsupportedLanguage(language)
                )
            }
            do {
                try embedding.load()
            } catch {
                throw SemanticEmbeddingError.modelLoadFailed(underlying: error)
            }
            let result: NLContextualEmbeddingResult
            do {
                result = try embedding.embeddingResult(for: snippet, language: language)
            } catch {
                throw SemanticEmbeddingError.inferenceFailed(reason: "\(error)")
            }

            let dimension = embedding.dimension
            var pooled = [Float](repeating: 0, count: dimension)
            var tokenCount = 0
            result.enumerateTokenVectors(in: snippet.startIndex..<snippet.endIndex) { vector, _ in
                guard vector.count == dimension else { return true }
                for index in 0..<dimension { pooled[index] += Float(vector[index]) }
                tokenCount += 1
                return true
            }
            if tokenCount > 0 {
                let scale = 1.0 / Float(tokenCount)
                for index in 0..<dimension { pooled[index] *= scale }
            }
            return pooled
        }
    }

    /// Why ``NLContextualSemanticEmbeddingProvider`` could not load, wrapped by
    /// ``SemanticEmbeddingError/modelLoadFailed(underlying:)``.
    public enum NLContextualEmbeddingError: Error, CustomStringConvertible {
        /// No `NLContextualEmbedding` for the requested language.
        case unsupportedLanguage(NLLanguage)
        /// The model assets are not downloaded and not reachable (offline, sandbox).
        case assetsUnavailable

        public var description: String {
            switch self {
            case .unsupportedLanguage(let language):
                "NLContextualEmbedding does not support language: \(language.rawValue)"
            case .assetsUnavailable:
                "NLContextualEmbedding model assets are not available locally; "
                    + "download them first via NLContextualEmbedding.requestEmbeddingAssets(...)."
            }
        }
    }

    /// The providers a tool starts from.
    public enum SemanticEmbeddingProviders {
        /// The zero-download provider: `NLContextualEmbedding` when its asset is there, else
        /// ``DeterministicEmbeddingProvider``, so a ranking or a score still runs offline with nothing to install.
        public static func onDeviceOrFallback() -> any SemanticEmbeddingProvider {
            if let contextual = try? NLContextualSemanticEmbeddingProvider() { return contextual }
            return DeterministicEmbeddingProvider()
        }
    }
#endif
