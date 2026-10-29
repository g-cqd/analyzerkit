/// The baseline file every analyzer reads and writes: the accepted fingerprints, sorted and unique, and the tool that
/// wrote them; arcleak, deadwood and dolly also write `version: 1`, fcheck does not (ADR-0017 keeps both shapes). A
/// tool keeps its own fingerprint (ADR-0017) and its own encoder.
public struct BaselineFile: Codable, Sendable, Equatable {
    public enum Failure: Error, Equatable, Sendable, CustomStringConvertible {
        case missingVersion
        case unsupportedVersion(Int)

        public var description: String {
            switch self {
            case .missingVersion: "the baseline has no version"
            case .unsupportedVersion(let version): "unsupported baseline version \(version)"
            }
        }
    }

    public let fingerprints: [String]
    public let tool: String
    public let version: Int?

    public init(tool: String, fingerprints: some Sequence<String>, versioned: Bool) {
        self.fingerprints = Set(fingerprints).sorted()
        self.tool = tool
        version = versioned ? 1 : nil
    }

    /// A decoded baseline this version of the tools can use: version 1, or no version where the tool writes none.
    public func validated(requiringVersion: Bool) throws(Failure) -> BaselineFile {
        switch version {
        case 1: return self
        case nil: if requiringVersion { throw .missingVersion } else { return self }
        case let other?: throw .unsupportedVersion(other)
        }
    }
}
