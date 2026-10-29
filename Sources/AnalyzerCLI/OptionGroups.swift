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
    public func message(tool: String) -> String { "" }
}

/// What to analyze.
public struct InputOptions: ParsableArguments, Sendable {
    @Argument(help: "Swift files or directories to analyze (default: the current directory).")
    public var paths: [String] = ["."]

    @Option(help: "Configuration file (default: the tool's configuration file in the current directory, when present).")
    public var config: String?

    @Option(
        name: .customLong("exclude-path"),
        help: "Leave out the paths matching this pattern (repeatable): a substring, or a glob with *, ? or [.")
    public var excludePaths: [String] = []

    @Option(
        name: .customLong("include-regions"),
        help: "Regions to treat as first-class code: preview,debug,test,mock,generated,script, or all.")
    var includeRegionsValue: String?

    @Option(
        name: .customLong("exclude-regions"), help: "Regions to keep out of scope, even under --include-regions all.")
    var excludeRegionsValue: String?

    @Option(name: .customLong("define"), help: "An #if condition to treat as set (repeatable; the compiler's -D).")
    public var defines: [String] = []

    @Option(help: "Report only findings in this file (repeatable); the whole corpus is still analyzed.")
    public var only: [String] = []

    @Option(name: .customLong("only-from"), help: "Read --only paths from a file, one per line ('-' reads stdin).")
    public var onlyFrom: String?

    @Option(name: .customLong("include"), help: .hidden) var includeAlias: String?
    @Option(name: .customLong("exclude"), help: .hidden) var excludeAlias: String?
    @Flag(name: .customLong("include-tests"), help: .hidden) var includeTestsAlias = false

    public init() {}

    /// `--include-regions`, with the deprecated `--include` and `--include-tests` folded in.
    public var includeRegions: String? { includeRegionsValue }
    /// `--exclude-regions`, with the deprecated `--exclude` folded in.
    public var excludeRegions: String? { excludeRegionsValue }
    /// The deprecated spellings this invocation used.
    public var deprecations: [Deprecation] { [] }
}

/// The report and how the run ends.
public struct OutputOptions: ParsableArguments, Sendable {
    public enum Format: String, CaseIterable, ExpressibleByArgument, Sendable { case xcode, json, sarif }

    @Option(help: "Output format: xcode (build-log diagnostics), json, or sarif.")
    public var format: Format = .xcode

    @Option(
        name: .customLong("relative-to"), help: "Report paths relative to this directory (use `--relative-to .` in CI)."
    )
    public var relativeTo: String?

    @Flag(help: "Fail on warnings as well as errors; notes never fail a run.")
    public var strict = false

    @Option(help: "Baseline file: findings whose fingerprints it holds are left out.")
    public var baseline: String?

    @Option(
        name: .customLong("write-baseline"), help: "Write the current findings as a baseline to this file, then exit 0."
    )
    public var writeBaseline: String?

    @Option(
        name: .customLong("report-new-since"),
        help: "The base branch's baseline file: findings outside --only that it does not hold are reported as new.")
    public var reportNewSince: String?

    @Flag(help: "Say more on stderr: every path of a note, and why a capability was or was not used.")
    public var verbose = false

    @Flag(help: "Print nothing on stderr but errors.")
    public var quiet = false

    @Flag(help: "Add the time each phase took to the report and to stderr.")
    public var timings = false

    public init() {}
}

/// Which rules run.
public struct RuleOptions: ParsableArguments, Sendable {
    @Option(name: .customLong("rules"), help: "Only these rules, comma-separated (see the `rules` subcommand).")
    var rulesValue: String?

    public init() {}

    /// The rule ids named by `--rules`, in order; nil without it.
    public var rules: [String]? { nil }
}

/// The per-file facts cache.
public struct CacheOptions: ParsableArguments, Sendable {
    @Option(
        name: .customLong("cache-path"),
        help: "Facts-cache file (default: a per-workspace file in the user cache directory).")
    public var cachePath: String?

    @Flag(name: .customLong("no-cache"), help: "Do not read or write the facts cache.")
    public var noCache = false

    public init() {}
}

/// The compiler's index store, for the tools that can read it.
public struct IndexOptions: ParsableArguments, Sendable {
    @Flag(name: .customLong("index-store"), help: "Use the compiler's index store (macOS), discovered for the project.")
    var indexStoreFlag = false

    @Option(name: .customLong("index-store-path"), help: "The index store to use; implies --index-store.")
    public var indexStorePath: String?

    @Flag(
        name: .customLong("index-store-build"),
        help: "Build the project for an index store when none is found; implies --index-store.")
    public var indexStoreBuild = false

    public init() {}

    /// Whether any index-store option was given.
    public var requested: Bool { false }
}

/// Experiments: they change ordering or confidence, never which findings fire.
public struct ExperimentalOptions: ParsableArguments, Sendable {
    public enum Embeddings: String, CaseIterable, ExpressibleByArgument, Sendable { case rank, confidence }

    @Option(
        name: .customLong("experimental-embeddings"),
        help: "Use embeddings to rank findings by similarity (rank) or to adjust their confidence (confidence).")
    var embeddingsValue: Embeddings?

    @Option(name: .customLong("embedding-bundle"), help: "A Core ML model bundle for --experimental-embeddings.")
    public var embeddingBundle: String?

    @Flag(name: .customLong("experimental-embedding-rank"), help: .hidden) var rankAlias = false
    @Flag(name: .customLong("experimental-embedding-confidence"), help: .hidden) var confidenceAlias = false

    public init() {}

    /// `--experimental-embeddings`, with the deprecated flags folded in.
    public var embeddings: Embeddings? { embeddingsValue }
    /// The deprecated spellings this invocation used.
    public var deprecations: [Deprecation] { [] }
}
