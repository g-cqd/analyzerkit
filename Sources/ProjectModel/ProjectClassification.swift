public import SwiftSyntax

#if canImport(FoundationEssentials)
    internal import FoundationEssentials
#else
    internal import Foundation
#endif

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
    /// Projects whose targets could not be read without running them, sorted by path.
    public let unknownProjects: [UnknownProject]
    private let packages: [String: Package]
    private let projects: [Project]

    /// A package's targets with their directories resolved; nil targets when the manifest is unknown.
    struct Package: Sendable {
        var manifest: String
        var targets: [ResolvedTarget]?
    }

    struct ResolvedTarget: Sendable {
        var target: ProjectTarget
        var root: String
        var sources: [String]?
        var exclude: [String]
    }

    struct Project: Sendable {
        var container: String
        var directory: String
        var model: XcodeProjectModel?
        var targets: [ProjectTarget]
    }

    init(unknownProjects: [UnknownProject], packages: [String: Package] = [:], projects: [Project] = []) {
        self.unknownProjects = unknownProjects.sorted { $0.path < $1.path }
        self.packages = packages
        self.projects = projects
    }

    /// A classification that knows no project: conventions only.
    public static let conventionsOnly = Self(unknownProjects: [])

    /// Reads every manifest and Xcode project of `layout`.
    public static func load(_ layout: ProjectLayout) -> Self {
        var unknown: [UnknownProject] = []
        var packages: [String: Package] = [:]
        for directory in layout.packages {
            let manifest = directory + "/Package.swift"
            guard let data = FileManager.default.contents(atPath: manifest) else {
                unknown.append(UnknownProject(path: manifest, reason: "the manifest cannot be read"))
                packages[directory] = Package(manifest: manifest, targets: nil)
                continue
            }
            switch PackageManifestReader.read(String(decoding: data, as: UTF8.self)) {
            case .unknown(let reason):
                unknown.append(UnknownProject(path: manifest, reason: reason))
                packages[directory] = Package(manifest: manifest, targets: nil)
            case .targets(let declared):
                packages[directory] = Package(
                    manifest: manifest, targets: declared.compactMap { resolve($0, in: directory, manifest: manifest) })
            }
        }
        var projects: [Project] = []
        for container in layout.containers where container.hasSuffix(".xcodeproj") {
            let directory = ProjectPaths.parent(container)
            guard let data = FileManager.default.contents(atPath: container + "/project.pbxproj") else {
                unknown.append(UnknownProject(path: container, reason: "project.pbxproj cannot be read"))
                projects.append(Project(container: container, directory: directory, model: nil, targets: []))
                continue
            }
            switch XcodeProjectReader.read(Array(data), container: container) {
            case .unknown(let reason):
                unknown.append(UnknownProject(path: container, reason: reason))
                projects.append(Project(container: container, directory: directory, model: nil, targets: []))
            case .project(let model):
                let targets = model.targets.map {
                    ProjectTarget(
                        name: $0.name, kind: $0.productType,
                        isTest: XcodeProjectReader.testProductTypes.contains($0.productType), container: container)
                }
                projects.append(Project(container: container, directory: directory, model: model, targets: targets))
            }
        }
        return Self(unknownProjects: unknown, packages: packages, projects: projects)
    }

    /// SwiftPM's directory for a target: its `path:`, or the first default directory that exists.
    private static func resolve(_ declared: DeclaredPackageTarget, in directory: String, manifest: String)
        -> ResolvedTarget?
    {
        guard declared.kind != "binaryTarget" else { return nil }
        let root: String
        if let path = declared.path {
            root = ProjectPaths.join(directory, path)
        } else {
            let parents: [String] =
                switch declared.kind {
                case "testTarget": ["Tests", "Sources", "Source", "src", "srcs"]
                case "plugin": ["Plugins"]
                default: ["Sources", "Source", "src", "srcs"]
                }
            let candidates = parents.map { directory + "/" + $0 + "/" + declared.name }
            root = candidates.first { FileManager.default.fileExists(atPath: $0) } ?? candidates[0]
        }
        let target = ProjectTarget(
            name: declared.name, kind: declared.kind, isTest: declared.kind == "testTarget", container: manifest)
        return ResolvedTarget(
            target: target, root: root, sources: declared.sources.map { $0.map { ProjectPaths.join(root, $0) } },
            exclude: declared.exclude.map { ProjectPaths.join(root, $0) })
    }

    /// The region of the file at `path` (canonical) from the project, or from path conventions when no project claims
    /// it.
    public func classify(_ path: String) -> FileClassification {
        let ancestors = Self.ancestors(of: path)
        let packageDirectory = ancestors.dropFirst().first { packages[$0] != nil }
        if let packageDirectory, Self.isManifest(path, in: packageDirectory) {
            return FileClassification(region: .script, provenance: .manifest)
        }
        for project in projects {
            if let phase = project.model?.scripts[path] {
                return FileClassification(
                    region: .script, provenance: .runScript(phase: phase, container: project.container))
            }
        }
        var targets: Set<ProjectTarget> = []
        var unknown: String?
        var enclosed = false
        if let packageDirectory, let package = packages[packageDirectory] {
            enclosed = true
            if let resolved = package.targets {
                for candidate in resolved where Self.contains(candidate, path) { targets.insert(candidate.target) }
            } else {
                unknown = package.manifest
            }
        }
        var output: (phase: String, container: String)?
        for project in projects where Self.isAtOrUnder(path, project.directory) {
            enclosed = true
            guard let model = project.model else {
                if packageDirectory == nil { unknown = unknown ?? project.container }
                continue
            }
            for ancestor in ancestors {
                for membership in model.memberships[ancestor] ?? []
                where !membership.excluded.contains(where: { Self.isAtOrUnder(path, $0) }) {
                    targets.insert(project.targets[membership.target])
                }
            }
            if let phase = model.outputs[path] { output = (phase, project.container) }
        }
        var region: CodeRegion = GeneratedCode.isGenerated(path: path, header: "") ? .generated : []
        if output != nil { region.insert(.generated) }
        if !targets.isEmpty {
            if targets.allSatisfy(\.isTest) { region.insert(.test) }
            return FileClassification(region: region, provenance: .targets(targets.sorted()))
        }
        if let output {
            return FileClassification(
                region: region, provenance: .buildOutput(phase: output.phase, container: output.container))
        }
        if TestConventions.isTestPath(path) { region.insert(.test) }
        let reason: ConventionReason = unknown.map { .unknownProject($0) } ?? (enclosed ? .unclaimed : .noProject)
        return FileClassification(region: region, provenance: .convention(reason))
    }

    /// ``classify(_:)`` with the file's content signals on top: a test framework import makes it test, a generator's
    /// header makes it generated.
    public func classify(_ path: String, tree: SourceFileSyntax) -> FileClassification {
        classify(path, content: Self.contentRegion(path: path, tree: tree))
    }

    /// What the file's content alone says of its region: test for a test-framework import, generated for a generator's
    /// header (or a generated name). It depends on the file only, so a facts cache keyed by content may keep it; the
    /// project's part changes without the file changing, and is joined per run by ``classify(_:content:)``.
    public static func contentRegion(path: String, tree: SourceFileSyntax) -> CodeRegion {
        var region: CodeRegion = []
        if TestConventions.importsTestFramework(tree) { region.insert(.test) }
        if GeneratedCode.isGenerated(path: path, tree: tree) { region.insert(.generated) }
        return region
    }

    /// ``classify(_:)`` joined with a ``contentRegion(path:tree:)`` computed earlier, perhaps cached.
    public func classify(_ path: String, content: CodeRegion) -> FileClassification {
        let base = classify(path)
        return FileClassification(region: base.region.union(content), provenance: base.provenance)
    }

    /// What the run should report about `paths`: files under projects that could not be read, and files inside a
    /// project that no target compiles. Both were classified by path conventions.
    public func issues(for paths: [String]) -> [ClassificationIssue] {
        var unknown: [String] = []
        var unclaimed: [String] = []
        for path in paths {
            switch classify(path).provenance {
            case .convention(.unknownProject): unknown.append(path)
            case .convention(.unclaimed): unclaimed.append(path)
            default: continue
            }
        }
        var issues: [ClassificationIssue] = []
        if !unknown.isEmpty {
            let projects = unknownProjects.map { "\($0.path): \($0.reason)" }.joined(separator: "; ")
            issues.append(
                ClassificationIssue(
                    code: "project-unknown",
                    message:
                        "\(unknown.count) file(s) are in a project that cannot be read without running it (\(projects)); "
                        + "path conventions classified them",
                    paths: unknown.sorted()))
        }
        if !unclaimed.isEmpty {
            issues.append(
                ClassificationIssue(
                    code: "project-unclaimed",
                    message:
                        "\(unclaimed.count) file(s) are in a project but no target compiles them; path conventions classified them",
                    paths: unclaimed.sorted()))
        }
        return issues
    }

    // MARK: Paths

    private static func isManifest(_ path: String, in directory: String) -> Bool {
        guard ProjectPaths.parent(path) == directory else { return false }
        let name = path[path.index(after: path.lastIndex(of: "/") ?? path.startIndex)...]
        return name == "Package.swift" || (name.hasPrefix("Package@swift-") && name.hasSuffix(".swift"))
    }

    private static func contains(_ target: ResolvedTarget, _ path: String) -> Bool {
        guard isAtOrUnder(path, target.root) else { return false }
        if let sources = target.sources, !sources.contains(where: { isAtOrUnder(path, $0) }) { return false }
        return !target.exclude.contains { isAtOrUnder(path, $0) }
    }

    static func isAtOrUnder(_ path: String, _ directory: String) -> Bool {
        path == directory || directory == "/"
            || (path.hasPrefix(directory) && path.utf8.dropFirst(directory.utf8.count).first == UInt8(ascii: "/"))
    }

    /// `path` itself, then each enclosing directory up to `/`.
    /// `path` and each of its parents, ending at `/` for an absolute path and at `.` for a relative one.
    static func ancestors(of path: String) -> [String] {
        var result = [path]
        var current = path
        while current != "/", !current.isEmpty {
            let parent = ProjectPaths.parent(current)
            // A bare name's parent is `.`, and `.`'s is `.` again: stop at the fixed point.
            guard parent != current else { break }
            current = parent
            result.append(current)
        }
        return result
    }
}
