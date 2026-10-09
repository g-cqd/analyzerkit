/// A finding as report scoping sees it: the file it is anchored in and the files of its related locations.
public protocol ScopedFinding {
    /// The canonical absolute path of the finding's primary location.
    var path: String { get }
    /// The canonical absolute paths of the finding's related locations: other
    /// clone-group members, other links of a cycle. Empty by default.
    var relatedPaths: [String] { get }
}

extension ScopedFinding {
    public var relatedPaths: [String] { [] }
}

/// The files a report is limited to, such as the `--only` file list of an analyzer.
///
/// The whole corpus is analyzed; only the report is scoped. A finding is kept
/// when any of its locations, primary or related, is in scope. The scope is a
/// set of canonical paths, and the tool canonicalizes its entries the same way
/// it canonicalizes findings, so a path option such as `--relative-to` changes
/// only how paths are printed, never what is kept. An empty scope, such as an
/// empty `--only-from` file, keeps nothing: the report is empty and, having no
/// findings, exits 0. "No scope" is expressed by the caller as a `ReportScope?`
/// that is nil, never by an empty scope.
public struct ReportScope: Sendable, Equatable {
    public let files: Set<String>

    public var isEmpty: Bool { files.isEmpty }

    /// - Parameter canonicalize: Maps each entry to the spelling the findings' paths use. The default keeps entries as given.
    public init(files: some Sequence<String>, canonicalize: (String) -> String = { $0 }) {
        self.files = Set(files.map(canonicalize))
    }

    /// True when the finding's path or any of its related paths is in scope.
    public func contains(_ finding: some ScopedFinding) -> Bool {
        files.contains(finding.path) || finding.relatedPaths.contains { files.contains($0) }
    }

    /// Splits findings into in-scope and out-of-scope, each keeping the input order.
    public func filter<Finding: ScopedFinding>(_ findings: [Finding]) -> (inScope: [Finding], outOfScope: [Finding]) {
        var inScope: [Finding] = []
        var outOfScope: [Finding] = []
        for finding in findings {
            if contains(finding) {
                inScope.append(finding)
            } else {
                outOfScope.append(finding)
            }
        }
        return (inScope, outOfScope)
    }
}
