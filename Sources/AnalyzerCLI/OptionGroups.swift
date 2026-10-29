public import ArgumentParser

/// The option groups every analyzer's analysing command uses, in this order (ADR-0019). A tool declares each with
/// `@OptionGroup(title: OptionGroupTitle.input) var input: InputOptions` and lists its own options after them.
public enum OptionGroupTitle {
    public static let input = "Input"
    public static let output = "Output"
    public static let rules = "Rules"
    public static let cache = "Cache"
    public static let index = "Index store"
    public static let experimental = "Experimental"
}

/// A renamed option that was used: printed once on stderr, never on stdout (ADR-0019).
public struct Deprecation: Sendable, Equatable {
    public let old: String
    public let new: String

    public init(old: String, new: String) {
        self.old = old
        self.new = new
    }

    /// `<tool>: note: <old> is deprecated; use <new>`.
    public func message(tool: String) -> String { "\(tool): note: \(old) is deprecated; use \(new)" }
}

/// What to analyze.
public struct InputOptions: ParsableArguments, Sendable {
    @Argument(help: "Swift files or directories to analyze.")
    public var paths: [String] = ["."]

    @Option(
        help: ArgumentHelp(
            "Configuration file (default: the tool's configuration file in the current directory, when present).",
            valueName: "file"))
    public var config: String?

    @Option(
        name: .customLong("exclude-path"),
        help: ArgumentHelp(
            "Leave out the paths matching this pattern (repeatable): a substring, or a glob with *, ? or [.",
            valueName: "pattern"))
    public var excludePaths: [String] = []

    @Option(
        name: .customLong("include-regions"),
        help: ArgumentHelp(
            "Regions to treat as first-class code: preview,debug,test,mock,generated,script, or all.", valueName: "list"
        ))
    var includeRegionsValue: String?

    @Option(
        name: .customLong("exclude-regions"),
        help: ArgumentHelp("Regions to keep out of scope, even under --include-regions all.", valueName: "list"))
    var excludeRegionsValue: String?

    @Option(
        name: .customLong("define"),
        help: ArgumentHelp("An #if condition to treat as set (repeatable; the compiler's -D).", valueName: "name"))
    public var defines: [String] = []

    @Option(
        help: ArgumentHelp(
            "Report only findings in this file (repeatable); the whole corpus is still analyzed.", valueName: "file"))
    public var only: [String] = []

    @Option(
        name: .customLong("only-from"),
        help: ArgumentHelp("Read --only paths from a file, one per line ('-' reads stdin).", valueName: "file"))
    public var onlyFrom: String?

    @Option(name: .customLong("include"), help: .hidden) var includeAlias: String?
    @Option(name: .customLong("exclude"), help: .hidden) var excludeAlias: String?
    @Flag(name: .customLong("include-tests"), help: .hidden) var includeTestsAlias = false

    public init() {}

    /// `--include-regions`, with the deprecated `--include` and `--include-tests` folded in.
    public var includeRegions: String? {
        Self.joined([includeRegionsValue, includeAlias, includeTestsAlias ? "test,generated" : nil])
    }
    /// `--exclude-regions`, with the deprecated `--exclude` folded in.
    public var excludeRegions: String? { Self.joined([excludeRegionsValue, excludeAlias]) }
    /// The deprecated spellings this invocation used.
    public var deprecations: [Deprecation] {
        var used: [Deprecation] = []
        if includeAlias != nil { used.append(Deprecation(old: "--include", new: "--include-regions")) }
        if excludeAlias != nil { used.append(Deprecation(old: "--exclude", new: "--exclude-regions")) }
        if includeTestsAlias {
            used.append(Deprecation(old: "--include-tests", new: "--include-regions test,generated"))
        }
        return used
    }

    /// The region lists given, as one comma-separated list; nil when none was.
    private static func joined(_ lists: [String?]) -> String? {
        let given = lists.compactMap(\.self)
        return given.isEmpty ? nil : given.joined(separator: ",")
    }
}

/// The report and how the run ends.
public struct OutputOptions: ParsableArguments, Sendable {
    public enum Format: String, CaseIterable, ExpressibleByArgument, Sendable { case xcode, json, sarif }

    @Option(help: "Output format: xcode (build-log diagnostics), json, or sarif.")
    public var format: Format = .xcode

    @Option(
        name: .customLong("relative-to"),
        help: ArgumentHelp(
            "Report paths relative to this directory (use `--relative-to .` in CI).", valueName: "directory"))
    public var relativeTo: String?

    @Flag(help: "Fail on warnings as well as errors; notes never fail a run.")
    public var strict = false

    @Option(help: ArgumentHelp("Baseline file: findings whose fingerprints it holds are left out.", valueName: "file"))
    public var baseline: String?

    @Option(
        name: .customLong("write-baseline"),
        help: ArgumentHelp("Write the current findings as a baseline to this file, then exit 0.", valueName: "file"))
    public var writeBaseline: String?

    @Option(
        name: .customLong("report-new-since"),
        help: ArgumentHelp(
            "The base branch's baseline file: findings outside --only that it does not hold are reported as new.",
            valueName: "file"))
    public var reportNewSince: String?

    @Flag(help: "Say more on stderr: every path of a note, and why a capability was or was not used.")
    public var verbose = false

    @Flag(help: "Print nothing on stderr but errors.")
    public var quiet = false

    @Flag(help: "Add the time each phase took to the report and to stderr.")
    public var timings = false

    public init() {}

    public func validate() throws {
        if verbose, quiet { throw ValidationError("--verbose and --quiet contradict each other; give one") }
    }
}

/// Which rules run.
public struct RuleOptions: ParsableArguments, Sendable {
    @Option(
        name: .customLong("rules"),
        help: ArgumentHelp("Only these rules, comma-separated (see the `rules` subcommand).", valueName: "list"))
    var rulesValue: String?

    public init() {}

    /// The rule ids named by `--rules`, in order; nil without it.
    public var rules: [String]? {
        rulesValue.map { $0.split(separator: ",").map { String($0).trimmingSpaces() }.filter { !$0.isEmpty } }
    }
}

/// The per-file facts cache.
public struct CacheOptions: ParsableArguments, Sendable {
    @Option(
        name: .customLong("cache-path"),
        help: ArgumentHelp(
            "Facts-cache file (default: a per-workspace file in the user cache directory).", valueName: "file"))
    public var cachePath: String?

    @Flag(name: .customLong("no-cache"), help: "Do not read or write the facts cache.")
    public var noCache = false

    public init() {}
}

/// The compiler's index store, for the tools that can read it.
public struct IndexOptions: ParsableArguments, Sendable {
    @Flag(name: .customLong("index-store"), help: "Use the compiler's index store (macOS), discovered for the project.")
    var indexStoreFlag = false

    @Option(
        name: .customLong("index-store-path"),
        help: ArgumentHelp("The index store to use; implies --index-store.", valueName: "path"))
    public var indexStorePath: String?

    @Flag(
        name: .customLong("index-store-build"),
        help: "Build the project for an index store when none is found; implies --index-store.")
    public var indexStoreBuild = false

    public init() {}

    /// Whether any index-store option was given.
    public var requested: Bool { indexStoreFlag || indexStorePath != nil || indexStoreBuild }
}

/// Experiments: they change ordering or confidence, never which findings fire.
public struct ExperimentalOptions: ParsableArguments, Sendable {
    public enum Embeddings: String, CaseIterable, ExpressibleByArgument, Sendable { case rank, confidence }

    @Option(
        name: .customLong("experimental-embeddings"),
        help: ArgumentHelp(
            "Use embeddings to rank findings by similarity (rank) or to adjust their confidence (confidence).",
            valueName: "kind"))
    var embeddingsValue: Embeddings?

    @Option(
        name: .customLong("embedding-bundle"),
        help: ArgumentHelp("A Core ML model bundle for --experimental-embeddings.", valueName: "path"))
    public var embeddingBundle: String?

    @Flag(name: .customLong("experimental-embedding-rank"), help: .hidden) var rankAlias = false
    @Flag(name: .customLong("experimental-embedding-confidence"), help: .hidden) var confidenceAlias = false

    public init() {}

    /// `--experimental-embeddings`, with the deprecated flags folded in.
    public var embeddings: Embeddings? { embeddingsValue ?? (rankAlias ? .rank : confidenceAlias ? .confidence : nil) }
    /// The deprecated spellings this invocation used.
    public var deprecations: [Deprecation] {
        var used: [Deprecation] = []
        if rankAlias {
            used.append(Deprecation(old: "--experimental-embedding-rank", new: "--experimental-embeddings rank"))
        }
        if confidenceAlias {
            used.append(
                Deprecation(old: "--experimental-embedding-confidence", new: "--experimental-embeddings confidence"))
        }
        return used
    }

    public func validate() throws {
        let chosen = [embeddingsValue, rankAlias ? .rank : nil, confidenceAlias ? .confidence : nil].compactMap(\.self)
        if Set(chosen).count > 1 {
            throw ValidationError("give one of --experimental-embeddings rank or confidence, not both")
        }
    }
}

extension String {
    /// The string without leading and trailing spaces and tabs.
    fileprivate func trimmingSpaces() -> String {
        let blank: (Character) -> Bool = { $0 == " " || $0 == "\t" }
        return String(drop(while: blank).reversed().drop(while: blank).reversed())
    }
}
