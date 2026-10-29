internal import SourceCorpus

#if canImport(FoundationEssentials)
    internal import FoundationEssentials
#else
    internal import Foundation
#endif

/// The project enclosing an analyzed corpus, independent of package nesting and worktree folder names.
public struct ProjectLayout: Sendable, Equatable {
    public let root: String
    public let repositoryRoot: String?
    /// Directories containing Package.swift, including local packages nested in an Xcode project.
    public let packages: [String]
    /// Absolute .xcodeproj and .xcworkspace directories, excluding workspaces embedded in projects.
    public let containers: [String]

    /// Starts at the common directory of all inputs and walks to the repository boundary (.git file or directory).
    /// The outermost ancestor with an Xcode container wins over packages; otherwise the outermost package wins,
    /// then the repository root, then the common directory. No analyzed-file ordering or folder-name heuristic.
    public static func discover(paths: [String]) -> Self? {
        guard let first = paths.first else { return nil }
        var common = directory(of: first)
        for path in paths.dropFirst() {
            let directory = directory(of: path)
            while common != "/" && directory != common && !directory.hasPrefix(common + "/") {
                common = URL(fileURLWithPath: common).deletingLastPathComponent().path
            }
        }
        let repository = RepositoryRoot.detect(from: common + "/")
        var cursor = common
        var xcode: String?
        var package: String?
        while true {
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: cursor)) ?? []
            if entries.contains(where: { isContainer($0) && isDirectory(join(cursor, $0)) }) { xcode = cursor }
            if entries.contains("Package.swift") { package = cursor }
            if cursor == repository || cursor == "/" { break }
            cursor = URL(fileURLWithPath: cursor).deletingLastPathComponent().path
        }
        let root = xcode ?? package ?? repository ?? common
        let manifests = SourceDiscovery.files(
            under: root,
            isExcluded: { path in
                // Xcode's private workspace is not an independently buildable container.
                let components = path.split(separator: "/")
                return components.dropLast().contains { $0.hasSuffix(".xcodeproj") }
                    && components.last?.hasSuffix(".xcworkspace") == true
            }
        ) { path in
            path.hasSuffix("/Package.swift") || path.hasSuffix(".xcodeproj/project.pbxproj")
                || path.hasSuffix(".xcworkspace/contents.xcworkspacedata")
        }
        var packages: Set<String> = []
        var containers: Set<String> = []
        for manifest in manifests {
            let parent = SourcePath.canonical(URL(fileURLWithPath: manifest).deletingLastPathComponent().path)
            if manifest.hasSuffix("/Package.swift") { packages.insert(parent) } else { containers.insert(parent) }
        }
        return Self(
            root: root, repositoryRoot: repository, packages: packages.sorted(), containers: containers.sorted())
    }

    /// Matching stores, newest first by LastAccessedDate (directory modification time if absent), then path.
    /// Each input is a DerivedData parent or a -derivedDataPath build root. Children require WorkspacePath metadata
    /// matching a container, never just a similar name. A directly supplied build root may omit metadata, but if it
    /// has metadata it must match too. Empty stores are left to the reader's format/population validation.
    public func derivedDataStores(under roots: [String]) -> [String] {
        var candidates: [String: Date] = [:]
        let containers = Set(containers)
        for root in roots {
            let root = SourcePath.canonical(root)
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
            for candidate in [root] + entries.map({ Self.join(root, $0) }) {
                let store = Self.join(candidate, "Index.noindex/DataStore")
                guard Self.isDirectory(store) else { continue }
                let metadata = Self.join(candidate, "info.plist")
                var accessed: Date?
                if FileManager.default.fileExists(atPath: metadata) {
                    guard let bytes = try? BoundedFileReader.read(path: metadata),
                        let plist = try? PropertyListDecoder().decode(DerivedDataMetadata.self, from: Data(bytes)),
                        containers.contains(SourcePath.canonical(plist.WorkspacePath))
                    else { continue }
                    accessed = plist.LastAccessedDate
                } else if candidate != root {
                    continue
                }
                let modified =
                    (try? FileManager.default.attributesOfItem(atPath: candidate))?[.modificationDate] as? Date
                candidates[SourcePath.canonical(store)] = accessed ?? modified ?? .distantPast
            }
        }
        return candidates.keys.sorted { lhs, rhs in
            let left = candidates[lhs] ?? .distantPast
            let right = candidates[rhs] ?? .distantPast
            return left == right ? lhs < rhs : left > right
        }
    }

    private struct DerivedDataMetadata: Decodable {
        let WorkspacePath: String
        let LastAccessedDate: Date?
    }

    private static func directory(of path: String) -> String {
        let canonical = SourcePath.canonical(path)
        if isDirectory(canonical) { return canonical }
        return URL(fileURLWithPath: canonical).deletingLastPathComponent().path
    }

    private static func isDirectory(_ path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType == .typeDirectory
    }

    private static func isContainer(_ name: String) -> Bool {
        name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace")
    }

    private static func join(_ directory: String, _ name: String) -> String {
        directory.hasSuffix("/") ? directory + name : directory + "/" + name
    }
}
