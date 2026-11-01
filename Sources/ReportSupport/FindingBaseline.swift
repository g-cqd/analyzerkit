internal import ProjectModel

#if canImport(FoundationEssentials)
    public import FoundationEssentials
#else
    public import Foundation
#endif

/// A set of accepted finding fingerprints: pre-existing debt a team adopts an analyzer against without a wall of
/// noise. Baselined findings leave the report and the exit code, and their count stays visible.
///
/// Fingerprints include line and column, so an unrelated edit above a finding moves it out of the baseline;
/// regenerate with `--write-baseline` after big moves. That is the deliberate trade against fuzzy matching, which
/// would swallow new bugs. The file is a ``BaselineFile`` with `version: 1`.
public struct FindingBaseline<Finding: Fingerprinted>: Sendable, Equatable {
    /// Why a baseline file was refused. The description is what the analyzers print after the path.
    public struct LoadFailure: Error, Equatable, Sendable, CustomStringConvertible {
        public let description: String
    }

    public let fingerprints: Set<String>

    public init(fingerprints: Set<String>) {
        self.fingerprints = fingerprints
    }

    public init(findings: [Finding]) {
        self.init(fingerprints: Set(findings.map(\.fingerprint)))
    }

    /// The baseline in `data`: well-formed JSON of a ``BaselineFile`` with version 1.
    public init(decoding data: Data) throws(LoadFailure) {
        let file: BaselineFile
        do {
            file = try JSONDecoder().decode(BaselineFile.self, from: data)
        } catch {
            throw LoadFailure(description: String(describing: error))
        }
        do {
            self.init(fingerprints: Set(try file.validated(requiringVersion: true).fingerprints))
        } catch {
            throw LoadFailure(description: error.description)
        }
    }

    public func contains(_ finding: Finding) -> Bool {
        fingerprints.contains(finding.fingerprint)
    }

    /// Splits findings into (kept, baselined), each in the order given.
    public func filter(_ findings: [Finding]) -> (kept: [Finding], baselined: [Finding]) {
        let (kept, baselined) = findings.partitioned(by: contains)
        return (kept, baselined)
    }

    /// The file's bytes: pretty-printed with sorted keys, so the same set always writes the same bytes.
    public func encoded(tool: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(BaselineFile(tool: tool, fingerprints: fingerprints, versioned: true))
    }
}
