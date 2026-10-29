import Foundation
import SourceCorpus
import Testing

/// The rule of ADR-0008, one row per behaviour: the substring entries every tool reads today (all of maintastic's), and
/// globs.
@Suite struct PathFilterTests {
    struct Row: CustomTestStringConvertible, Sendable {
        let entry: String
        let path: String
        let excluded: Bool
        var testDescription: String { "\(entry) on \(path) → \(excluded)" }
    }

    static let root = "/r"

    /// Substring entries: every configuration in use (maintastic's `.arcleak.json`, `.dolly.json`, `.deadwood.json`).
    static let substrings: [Row] = [
        Row(entry: "/Generated/", path: "/r/App/Generated/Assets.swift", excluded: true),
        Row(entry: "/Generated/", path: "/r/App/GeneratedCode/A.swift", excluded: false),
        Row(entry: ".swiftpm/", path: "/r/Pkg/.swiftpm/x.swift", excluded: true),
        Row(entry: ".build/", path: "/r/Pkg/.build/checkouts/A.swift", excluded: true),
        Row(entry: "DerivedData/", path: "/r/DerivedData/A.swift", excluded: true),
        Row(entry: "DangerPlugins/", path: "/r/DangerPlugins/Sources/P.swift", excluded: true),
        Row(entry: "AppStoreScreenshotUITests/", path: "/r/AppStoreScreenshotUITests/S.swift", excluded: true),
        Row(entry: "Package.swift", path: "/r/Package.swift", excluded: true),
        // The case ADR-0008 keeps: a substring entry still reaches a longer name.
        Row(entry: "Package.swift", path: "/r/Sources/MyPackage.swift", excluded: true),
        Row(entry: "Dangerfile.swift", path: "/r/Dangerfile.swift", excluded: true),
        Row(entry: "Dangerfile.hooks.swift", path: "/r/Dangerfile.hooks.swift", excluded: true),
        Row(entry: "Danger/", path: "/r/Danger/Rules.swift", excluded: true),
        Row(entry: "ShareXcodePlugins/", path: "/r/ShareXcodePlugins/Plugin.swift", excluded: true),
        Row(entry: "ShareMacros/Tests/", path: "/r/ShareMacros/Tests/MacroTests.swift", excluded: true),
        Row(entry: "ShareMacros/Tests/", path: "/r/ShareMacros/Sources/Macro.swift", excluded: false),
        Row(entry: "scripts/", path: "/r/Sources/myscripts/x.swift", excluded: true),
        Row(entry: "/Package.swift", path: "/r/Sources/MyPackage.swift", excluded: false),
        Row(entry: "", path: "/r/A.swift", excluded: false),
        // A directory is asked about with a trailing `/`, so a walk can prune it.
        Row(entry: "/Generated/", path: "/r/App/Generated/", excluded: true),
    ]

    /// Glob entries: relative to the root, `/` anchors there, otherwise at any depth.
    static let globs: [Row] = [
        Row(entry: "**/Package.swift", path: "/r/Package.swift", excluded: true),
        Row(entry: "**/Package.swift", path: "/r/Sources/MyPackage.swift", excluded: false),
        Row(entry: "/*.swift", path: "/r/Package.swift", excluded: true),
        Row(entry: "/*.swift", path: "/r/Sources/A.swift", excluded: false),
        Row(entry: "*.generated.swift", path: "/r/Sources/Deep/X.generated.swift", excluded: true),
        Row(entry: "**/Tests/**", path: "/r/Pkg/Tests/A/B.swift", excluded: true),
        Row(entry: "**/Tests/**", path: "/r/Pkg/MyTests/A.swift", excluded: false),
        Row(entry: "**/*Tests.swift", path: "/r/Pkg/Sources/FooTests.swift", excluded: true),
        Row(entry: "**/*Tests.swift", path: "/r/Pkg/FooTests/Foo.swift", excluded: false),
        Row(entry: "**/Fixtures/**", path: "/r/Tests/Fixtures/x.swift", excluded: true),
        // A directory that matches excludes what is under it, so filtering a list agrees with pruning a walk.
        Row(entry: "Sources/*/Internal", path: "/r/Sources/App/Internal/A.swift", excluded: true),
        Row(entry: "Sources/*/Internal", path: "/r/Sources/App/Internal.swift", excluded: false),
        Row(entry: "/Sources/**/Mock?.swift", path: "/r/Sources/a/b/Mock1.swift", excluded: true),
        Row(entry: "/Sources/**/Mock?.swift", path: "/r/Sources/Mock1.swift", excluded: true),
        Row(entry: "/Sources/**/Mock?.swift", path: "/r/Sources/Mock12.swift", excluded: false),
        Row(entry: "/Sources*.swift", path: "/r/Sources/A.swift", excluded: false),
        Row(entry: "[AB]*.swift", path: "/r/x/Alpha.swift", excluded: true),
        Row(entry: "[AB]*.swift", path: "/r/x/Gamma.swift", excluded: false),
        Row(entry: "[!A]*.swift", path: "/r/x/Alpha.swift", excluded: false),
        Row(entry: "[!A]*.swift", path: "/r/x/Beta.swift", excluded: true),
        Row(entry: "[a-c]?.swift", path: "/r/b1.swift", excluded: true),
        Row(entry: "[a-c]?.swift", path: "/r/d1.swift", excluded: false),
        Row(entry: "?.swift", path: "/r/é.swift", excluded: true),
        Row(entry: "[é]*.swift", path: "/r/école.swift", excluded: true),
        Row(entry: "[draft*.swift", path: "/r/[draft1.swift", excluded: true),
        Row(entry: "*", path: "/r/x/A.swift", excluded: true),
        // A trailing `/` matches directories only.
        Row(entry: "**/Build*/", path: "/r/BuildTools/x.swift", excluded: true),
        Row(entry: "**/Build*/", path: "/r/BuildTools.swift", excluded: false),
        // Directories, asked with a trailing `/`.
        Row(entry: "**/Generated/**", path: "/r/App/Generated/", excluded: true),
        Row(entry: "Sources/*/Internal", path: "/r/Sources/App/Internal/", excluded: true),
        Row(entry: "**/*Tests.swift", path: "/r/Pkg/Tests/", excluded: false),
        Row(entry: "/Sources/*.swift", path: "/r/Sources/", excluded: false),
        // Outside the root an anchored glob matches nothing; a floating one still reaches the name.
        Row(entry: "/*.swift", path: "/elsewhere/A.swift", excluded: false),
        Row(entry: "*.swift", path: "/elsewhere/A.swift", excluded: true),
        // A path already relative to the root.
        Row(entry: "/Sources/*.swift", path: "Sources/A.swift", excluded: true),
    ]

    @Test(arguments: substrings + globs)
    func `an entry excludes the paths it names and no other`(_ row: Row) {
        let filter = PathFilter([row.entry], root: Self.root)
        #expect(filter.excludes(row.path) == row.excluded)
    }

    @Test func `a filter excludes what any of its entries excludes, and an empty one nothing`() {
        let filter = PathFilter(["Package.swift", "**/Tests/**"], root: Self.root)
        #expect(filter.excludes("/r/Package.swift") && filter.excludes("/r/A/Tests/T.swift"))
        #expect(!filter.excludes("/r/Sources/A.swift"))
        #expect(!filter.isEmpty)
        #expect(PathFilter([], root: Self.root).isEmpty && PathFilter([""], root: Self.root).isEmpty)
    }

    @Test func `a root spelled with a trailing slash is the same root`() {
        #expect(PathFilter(["/*.swift"], root: "/r/").excludes("/r/A.swift"))
    }
}

/// A walk that prunes with the filter lists exactly what filtering the whole walk keeps, so a tool that walks and a tool
/// that is handed a list select the same files (roadmap 0005).
@Suite struct PathFilterWalkTests {
    static let fixture = [
        "Package.swift", "Sources/App/App.swift", "Sources/App/MyPackage.swift", "Sources/App/Generated/Assets.swift",
        "Sources/App/Internal/Secret.swift", "Sources/App/Internal.swift", "Sources/Kit/Mock1.swift",
        "Sources/Kit/Deep/Mock2.swift", "Tests/AppTests/AppTests.swift", "Tests/Fixtures/Input.swift",
        "BuildTools/Plugin.swift", "Danger/Rules.swift", "Dangerfile.swift", "école.swift",
    ]

    static let configurations: [[String]] = [
        [],
        ["/Generated/", "Package.swift", "Danger/", "Dangerfile.swift"],
        ["**/Package.swift", "**/Tests/**", "Sources/*/Internal"],
        ["/Sources/**/Mock?.swift", "**/Build*/", "[é]*.swift", "**/Fixtures/**"],
        ["*"],
    ]

    @Test(arguments: configurations)
    func `pruning the walk agrees with filtering the list`(_ entries: [String]) throws {
        try Scratch.with { scratch in
            for file in Self.fixture { try scratch.write(file) }
            let root = SourcePath.canonical(scratch.root.path)
            let filter = PathFilter(entries, root: root)
            let pruned = SourceDiscovery.swiftFiles(under: root, isExcluded: filter.excludes)
            let filtered = SourceDiscovery.swiftFiles(under: root).filter { !filter.excludes($0) }
            #expect(pruned == filtered)
            #expect(SourceDiscovery.swiftFiles(under: root).count == Self.fixture.count)
        }
    }

    @Test func `the files a configuration keeps`() throws {
        try Scratch.with { scratch in
            for file in Self.fixture { try scratch.write(file) }
            let root = SourcePath.canonical(scratch.root.path)
            let filter = PathFilter(["**/Package.swift", "**/Tests/**", "Sources/*/Internal", "/*.swift"], root: root)
            let kept = SourceDiscovery.swiftFiles(under: root, isExcluded: filter.excludes)
                .map { String($0.dropFirst(root.count + 1)) }
            #expect(
                kept == [
                    "BuildTools/Plugin.swift", "Danger/Rules.swift", "Sources/App/App.swift",
                    "Sources/App/Generated/Assets.swift", "Sources/App/Internal.swift", "Sources/App/MyPackage.swift",
                    "Sources/Kit/Deep/Mock2.swift", "Sources/Kit/Mock1.swift",
                ])
        }
    }
}
