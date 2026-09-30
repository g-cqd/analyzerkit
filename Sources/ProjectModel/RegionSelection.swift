/// The name each region answers to on the command line and in a config
/// file, the same spelling in every analyzer: `preview`, `debug`, `test`,
/// `mock`, `generated`, `script`, and `all` for the whole set.
extension CodeRegion {
    private static let namedRegions: [(name: String, region: CodeRegion)] = [
        ("preview", .preview),
        ("debug", .debugOnly),
        ("test", .test),
        ("mock", .mock),
        ("generated", .generated),
        ("script", .script),
    ]

    /// Every region `all` stands for.
    public static let allRegions: CodeRegion = namedRegions.reduce(into: []) { $0.formUnion($1.region) }

    /// The names this tool accepts, `all` included, for `--help` text.
    public static let regionNames: [String] = namedRegions.map(\.name) + ["all"]

    /// The region one name selects; nil for a name none of the tools know.
    public init?(name: String) {
        if name == "all" {
            self = Self.allRegions
            return
        }
        guard let match = Self.namedRegions.first(where: { $0.name == name }) else { return nil }
        self = match.region
    }

    /// The name(s) this region is made of, `all` when it is the whole set,
    /// comma-joined: the reverse of parsing, for messages and SARIF text
    /// (`region: preview` or `region: preview, debug`).
    public var names: String {
        if self == Self.allRegions { return "all" }
        let matched = Self.namedRegions.filter { self.contains($0.region) }.map(\.name)
        return matched.joined(separator: ", ")
    }
}

/// A comma-separated `--include`/`--exclude` argument (or config array),
/// parsed once. An unknown name is the caller's error to raise, not this
/// type's to swallow.
public enum RegionArgument {
    /// The regions named by a comma-separated list such as `preview,debug`
    /// or `all`.
    /// - Throws: the first name that matches no region.
    public static func parse(_ argument: String) throws(UnknownRegionName) -> CodeRegion {
        var region = CodeRegion.production
        for rawName in argument.split(separator: ",") {
            let name = String(rawName.trimmingWhitespace)
            guard !name.isEmpty else { continue }
            guard let matched = CodeRegion(name: name) else { throw UnknownRegionName(name: name) }
            region.formUnion(matched)
        }
        return region
    }
}

/// Raised when `--include`/`--exclude`, or the matching config key, names a
/// region no analyzer knows.
public struct UnknownRegionName: Error, Sendable, Equatable {
    public let name: String

    public init(name: String) {
        self.name = name
    }

    public var description: String {
        "unknown region \"\(name)\" — known regions: \(CodeRegion.regionNames.joined(separator: ", "))"
    }
}

/// What `--include`/`--exclude` (or their config-file keys) leave in scope:
/// `include` widens a region from suppressed-by-default to a first-class
/// finding source, `exclude` narrows one further. Excluding wins where the
/// two would otherwise disagree about the same region — an explicit
/// "leave this alone" is never overridden by a broader "include everything".
public struct RegionSelection: Sendable, Equatable {
    public let include: CodeRegion
    public let exclude: CodeRegion

    public static let none = RegionSelection(include: [], exclude: [])

    public init(include: CodeRegion, exclude: CodeRegion) {
        self.include = include
        self.exclude = exclude
    }

    /// Parse `--include`/`--exclude` arguments (or their config values);
    /// nil arguments leave that side empty.
    public init(include: String?, exclude: String?) throws(UnknownRegionName) {
        self.include = try include.map(RegionArgument.parse) ?? []
        self.exclude = try exclude.map(RegionArgument.parse) ?? []
    }

    /// Whether `region` should be treated as first-class production code
    /// for reporting: included, and not excluded.
    public func isIncluded(_ region: CodeRegion) -> Bool {
        guard !region.isEmpty else { return false }
        return region.isSubset(of: include) && !region.intersects(exclude)
    }
}

extension CodeRegion {
    /// Whether this region shares any flag with `other`.
    public func intersects(_ other: CodeRegion) -> Bool {
        !intersection(other).isEmpty
    }
}

extension Substring {
    /// This substring with leading and trailing spaces and tabs removed, no
    /// `Foundation` needed for a plain `--include preview, debug` split.
    fileprivate var trimmingWhitespace: Substring {
        var value = self
        while let first = value.first, first == " " || first == "\t" { value = value.dropFirst() }
        while let last = value.last, last == " " || last == "\t" { value = value.dropLast() }
        return value
    }
}
