/// The project enclosing an analyzed corpus, independent of package nesting and worktree folder names.
public struct ProjectLayout: Sendable, Equatable {
    public let root: String
    public let repositoryRoot: String?
    /// Directories containing Package.swift, including local packages nested in an Xcode project.
    public let packages: [String]
    /// Absolute .xcodeproj and .xcworkspace directories, excluding workspaces embedded in projects.
    public let containers: [String]

    public static func discover(paths: [String]) -> Self? { nil }

    /// Matching stores, newest first. Each input is a DerivedData parent or a -derivedDataPath build root.
    public func derivedDataStores(under roots: [String]) -> [String] { [] }
}
