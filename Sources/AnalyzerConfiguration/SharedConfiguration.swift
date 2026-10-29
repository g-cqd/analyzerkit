internal import AemiJSONCore
internal import OrderedCollections
internal import ProjectModel
internal import SourceCorpus

#if canImport(FoundationEssentials)
    internal import FoundationEssentials
#else
    internal import Foundation
#endif

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

        /// What is wrong, without the path, for a tool that reports the two apart.
        public var reason: String { "" }

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
        let files = try locate(
            tool: tool, explicit: explicit, currentDirectory: currentDirectory, analyzedPaths: analyzedPaths)
        var layers: [(source: Source, members: OrderedDictionary<String, JSONValue>)] = []
        for file in files {
            let members = try object(at: file.path)
            if file.isShared {
                layers += try sharedLayers(members, path: file.path, tool: tool)
            } else {
                for (key, value) in members {
                    try check(key, value, allowed: tool.keys, reported: key, path: file.path)
                }
                layers.append((Source(path: file.path), members))
            }
        }
        return try merged(layers, directory: files.first.map { Self.parent(of: $0.path) })
    }

    // MARK: - Finding the files

    private struct File {
        let path: String
        let isShared: Bool
    }

    /// The files of the one configuration directory, the shared file first (ADR-0020 item 1).
    private static func locate(
        tool: Tool, explicit: String?, currentDirectory: String, analyzedPaths: [String]
    ) throws(Failure) -> [File] {
        if let explicit {
            let path = absolute(explicit, in: currentDirectory)
            guard FileManager.default.fileExists(atPath: path) else {
                throw .unreadable(path: path, reason: "no such file")
            }
            return [File(path: path, isShared: URL(fileURLWithPath: path).lastPathComponent == fileName)]
        }
        func files(in directory: String) -> [File] {
            [(fileName, true), (tool.fileName, false)].compactMap { name, isShared in
                let path = directory.hasSuffix("/") ? directory + name : directory + "/" + name
                return FileManager.default.fileExists(atPath: path) ? File(path: path, isShared: isShared) : nil
            }
        }
        let here = files(in: currentDirectory)
        if !here.isEmpty { return here }
        let paths = analyzedPaths.map { absolute($0, in: currentDirectory) }
        guard let root = ProjectLayout.discover(paths: paths)?.root, root != currentDirectory else { return [] }
        return files(in: root)
    }

    private static func absolute(_ path: String, in directory: String) -> String {
        SourcePath.canonical(path.hasPrefix("/") ? path : directory + "/" + path)
    }

    private static func parent(of path: String) -> String {
        URL(fileURLWithPath: path).deletingLastPathComponent().path
    }

    // MARK: - Reading and checking

    private static func object(at path: String) throws(Failure) -> OrderedDictionary<String, JSONValue> {
        let data: Data
        do {
            data = try BoundedFileReader.readConfiguration(path: path)
        } catch {
            throw .unreadable(path: path, reason: "\(error)")
        }
        let value: JSONValue
        do {
            value = JSONValue(try AemiJSON.parse([UInt8](data)).root)
        } catch {
            throw .invalid(path: path, reason: "\(error)")
        }
        guard case .object(let members) = value else { throw .invalid(path: path, reason: "not a JSON object") }
        return members
    }

    /// The shared file's top level and this tool's section, each checked; other tools' sections only as objects.
    private static func sharedLayers(
        _ members: OrderedDictionary<String, JSONValue>, path: String, tool: Tool
    ) throws(Failure) -> [(source: Source, members: OrderedDictionary<String, JSONValue>)] {
        var top: OrderedDictionary<String, JSONValue> = [:]
        var section: OrderedDictionary<String, JSONValue>?
        for (key, value) in members {
            if sharedKeys.contains(key) {
                try checkType(key, value, path: path)
                top[key] = value
            } else if toolNames.contains(key) {
                guard case .object(let entries) = value else {
                    throw .invalid(path: path, reason: "\"\(key)\" is not an object")
                }
                guard key == tool.name else { continue }
                for (entry, entryValue) in entries {
                    try check(entry, entryValue, allowed: tool.keys, reported: "\(key).\(entry)", path: path)
                }
                section = entries
            } else {
                throw .unknownKey(path: path, key: key)
            }
        }
        var layers = [(source: Source(path: path), members: top)]
        if let section { layers.append((Source(path: path, section: tool.name), section)) }
        return layers
    }

    private static func check(
        _ key: String, _ value: JSONValue, allowed: Set<String>, reported: String, path: String
    ) throws(Failure) {
        if sharedKeys.contains(key) {
            try checkType(key, value, path: path)
        } else if !allowed.contains(key) {
            throw .unknownKey(path: path, key: reported)
        }
    }

    /// The shared keys' types: lists of strings, or a string for the region lists.
    private static func checkType(_ key: String, _ value: JSONValue, path: String) throws(Failure) {
        switch (key, value) {
        case ("includeRegions", .string), ("excludeRegions", .string): return
        case ("includeRegions", _), ("excludeRegions", _):
            throw .invalid(path: path, reason: "\"\(key)\" must be a string")
        case (_, .array(let items)) where items.allSatisfy({ if case .string = $0 { true } else { false } }): return
        default: throw .invalid(path: path, reason: "\"\(key)\" must be a list of strings")
        }
    }

    // MARK: - Merging

    /// The layers merged in order: objects key by key (RFC 7396), `exclude` lists concatenated, the rest replaced.
    private static func merged(
        _ layers: [(source: Source, members: OrderedDictionary<String, JSONValue>)], directory: String?
    ) throws(Failure) -> Resolved {
        var result: OrderedDictionary<String, JSONValue> = [:]
        var setters: OrderedDictionary<String, [Source]> = [:]
        for (source, members) in layers {
            for (key, value) in members {
                if key == "exclude", case .array(let added) = value {
                    guard case .array(let existing)? = result[key] else {
                        result[key] = value
                        setters[key, default: []].append(source)
                        continue
                    }
                    result[key] = .array(existing + added)
                } else {
                    result[key] = JSONMergePatch.apply(value, to: result[key] ?? .null)
                }
                setters[key, default: []].append(source)
            }
        }
        let overrides = setters.compactMap { key, sources -> Override? in
            guard sources.count > 1, let winner = sources.last else { return nil }
            return Override(key: key, winner: winner, overridden: Array(sources.dropLast()), combined: key == "exclude")
        }
        let json: [UInt8]
        do {
            json = try JSONValue.object(result).encodedBytes()
        } catch {
            throw .invalid(path: layers.last?.source.path ?? "", reason: "\(error)")
        }
        return Resolved(json: json, directory: directory, sources: layers.map(\.source), overrides: overrides)
    }
}

extension SharedConfiguration.Resolved {
    /// What `--verbose` prints about the configuration (ADR-0020 item 5): the files read, then each key more than one
    /// source set and which won.
    public func verboseLines(tool: String) -> [String] {
        let prefix = "\(tool): configuration: "
        guard !sources.isEmpty else { return [prefix + "no file found; built-in defaults"] }
        func list(_ sources: [SharedConfiguration.Source]) -> String {
            sources.map(\.description).joined(separator: ", ")
        }
        return [prefix + "read " + list(sources)]
            + overrides.map { override in
                override.combined
                    ? prefix + "\(override.key) combined from " + list(override.overridden + [override.winner])
                    : prefix + "\(override.key) from \(override.winner), over " + list(override.overridden)
            }
    }
}
