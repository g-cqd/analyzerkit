public import SwiftSyntax

/// A target that compiles a file: a SwiftPM target or an Xcode native target.
public struct ProjectTarget: Sendable, Hashable, Comparable {
    /// The target's name.
    public let name: String
    /// `testTarget`, `executableTarget`, … for a package; the product type for Xcode
    /// (`com.apple.product-type.application`, …).
    public let kind: String
    /// Whether the target only builds tests.
    public let isTest: Bool
    /// The `Package.swift` or `.xcodeproj` that declares it.
    public let container: String

    public init(name: String, kind: String, isTest: Bool, container: String) {
        self.name = name
        self.kind = kind
        self.isTest = isTest
        self.container = container
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.container, lhs.name) < (rhs.container, rhs.name)
    }
}

/// Where a file's classification came from (ADR-0024).
public enum ClassificationProvenance: Sendable, Hashable {
    /// The targets compiling the file, sorted.
    case targets([ProjectTarget])
    /// A package manifest: SwiftPM runs it, nothing ships it.
    case manifest
    /// A run-script phase runs it.
    case runScript(phase: String, container: String)
    /// A run-script phase writes it, or its reference lives in a build-products tree.
    case buildOutput(phase: String, container: String)
    /// No project said anything; path conventions decided.
    case convention(ConventionReason)
}

/// Why path conventions decided.
public enum ConventionReason: Sendable, Hashable {
    /// No package or Xcode project encloses the file.
    case noProject
    /// A project encloses the file, but none of its targets compiles it.
    case unclaimed
    /// The enclosing project could not be read without running it.
    case unknownProject(String)
}

/// A file's region as its project sees it, and why.
public struct FileClassification: Sendable, Hashable {
    public let region: CodeRegion
    public let provenance: ClassificationProvenance

    public init(region: CodeRegion, provenance: ClassificationProvenance) {
        self.region = region
        self.provenance = provenance
    }
}

/// A project that could not be read as data.
public struct UnknownProject: Sendable, Hashable {
    /// The `Package.swift` or `.xcodeproj`.
    public let path: String
    public let reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}

/// What the run should say about classification: a code, a message and the files concerned.
public struct ClassificationIssue: Sendable, Hashable {
    public let code: String
    public let message: String
    public let paths: [String]

    public init(code: String, message: String, paths: [String]) {
        self.code = code
        self.message = message
        self.paths = paths
    }
}

/// Test, generated and script code, classified from the packages and Xcode projects of a layout before any path
/// convention (ADR-0024). Built once per run; nothing is executed.
public struct ProjectClassification: Sendable {
    /// Projects whose targets could not be read without running them.
    public let unknownProjects: [UnknownProject]

    init(unknownProjects: [UnknownProject]) {
        self.unknownProjects = unknownProjects
    }

    /// Reads every manifest and project of `layout`. Red stub (roadmap 0043): reads nothing.
    public static func load(_ layout: ProjectLayout) -> Self {
        Self(unknownProjects: [])
    }

    /// A classification that knows no project: conventions only.
    public static let conventionsOnly = Self(unknownProjects: [])

    /// The region of the file at `path` (canonical) from the project, or from path conventions when no project claims
    /// it. Red stub: path conventions only.
    public func classify(_ path: String) -> FileClassification {
        var region: CodeRegion = []
        if TestConventions.isTestPath(path) { region.insert(.test) }
        if GeneratedCode.isGenerated(path: path, header: "") { region.insert(.generated) }
        return FileClassification(region: region, provenance: .convention(.noProject))
    }

    /// ``classify(_:)`` with the file's content signals on top: a test framework import makes it test, a generator's
    /// header makes it generated.
    public func classify(_ path: String, tree: SourceFileSyntax) -> FileClassification {
        let base = classify(path)
        var region = base.region
        if TestConventions.isTestFile(path: path, tree: tree) { region.insert(.test) }
        if GeneratedCode.isGenerated(path: path, tree: tree) { region.insert(.generated) }
        return FileClassification(region: region, provenance: base.provenance)
    }

    /// What the run should report about `paths`: files under unknown projects, and files no target claims. Red stub.
    public func issues(for paths: [String]) -> [ClassificationIssue] {
        []
    }
}
