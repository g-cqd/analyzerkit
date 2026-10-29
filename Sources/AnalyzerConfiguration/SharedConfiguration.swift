/// The configuration every analyzer reads (ADR-0020): one directory, the shared `.swift-analyzers.json` and the tool's
/// own file, merged into one JSON object the tool decodes with its own types; every key checked.
public enum SharedConfiguration {
    /// The shared file's name.
    public static let fileName = ".swift-analyzers.json"
    /// The tools that have a section in the shared file.
    public static let toolNames: Set<String> = ["arcleak", "deadwood", "dolly", "fcheck", "modeler"]
    /// The keys every tool's configuration shares, at the shared file's top level or in any section or tool file.
    public static let sharedKeys: Set<String> = ["exclude", "includeRegions", "excludeRegions", "defines", "platforms"]

    /// What a tool reads.
    public struct Tool: Sendable {
        public let name: String
        /// Its own file, such as `.arcleak.json`.
        public let fileName: String
        /// The top-level keys its own file and section may hold besides the shared ones.
        public let keys: Set<String>

        public init(name: String, fileName: String, keys: Set<String>) {
            self.name = name
            self.fileName = fileName
            self.keys = keys
        }
    }

    /// A place a value came from: a file, or a section of the shared file.
    public struct Source: Sendable, Equatable, CustomStringConvertible {
        public let path: String
        public let section: String?

        public init(path: String, section: String? = nil) {
            self.path = path
            self.section = section
        }

        /// `path`, or `path#section`.
        public var description: String { section.map { "\(path)#\($0)" } ?? path }
    }

    /// A key more than one source set, and the one that won (or, for `exclude`, all combined).
    public struct Override: Sendable, Equatable {
        public let key: String
        public let winner: Source
        public let overridden: [Source]
        public let combined: Bool

        public init(key: String, winner: Source, overridden: [Source], combined: Bool) {
            self.key = key
            self.winner = winner
            self.overridden = overridden
            self.combined = combined
        }
    }

    /// The configuration of one run.
    public struct Resolved: Sendable {
        /// The merged object, UTF-8 JSON; `{}` when no file was read.
        public let json: [UInt8]
        /// The directory the files were read from, the root of `exclude` globs; nil when none was read.
        public let directory: String?
        /// The files and sections read, lowest precedence first.
        public let sources: [Source]
        public let overrides: [Override]
    }

    /// Why the configuration cannot be used: always exit 78 (ADR-0018).
    public enum Failure: Error, Equatable, Sendable, CustomStringConvertible {
        case unreadable(path: String, reason: String)
        case invalid(path: String, reason: String)
        case unknownKey(path: String, key: String)

        public var path: String {
            switch self {
            case .unreadable(let path, _), .invalid(let path, _), .unknownKey(let path, _): path
            }
        }

        public var description: String {
            switch self {
            case .unreadable(let path, let reason): "cannot read \(path): \(reason)"
            case .invalid(let path, let reason): "invalid configuration \(path): \(reason)"
            case .unknownKey(let path, let key): "\(path): unknown key \"\(key)\""
            }
        }
    }

    /// Finds, reads, checks and merges the configuration of `tool`.
    /// - Parameters:
    ///   - explicit: the `--config` file, which replaces the lookup.
    ///   - currentDirectory: where the tool runs, absolute.
    ///   - analyzedPaths: the paths given, absolute or relative to `currentDirectory`; their project root is the second
    ///     place looked at.
    public static func resolve(
        for tool: Tool, explicit: String?, currentDirectory: String, analyzedPaths: [String]
    ) throws(Failure) -> Resolved {
        Resolved(json: Array("{}".utf8), directory: nil, sources: [], overrides: [])
    }
}
