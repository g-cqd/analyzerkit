import AnalyzerCLI
import ArgumentParser
import Foundation
import ProjectModel
import Testing

/// A command made of every shared group, as a tool's analysing command declares them (ADR-0019).
private struct Probe: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "probe")
    @OptionGroup(title: OptionGroupTitle.input) var input: InputOptions
    @OptionGroup(title: OptionGroupTitle.output) var output: OutputOptions
    @OptionGroup(title: OptionGroupTitle.rules) var rules: RuleOptions
    @OptionGroup(title: OptionGroupTitle.cache) var cache: CacheOptions
    @OptionGroup(title: OptionGroupTitle.index) var index: IndexOptions
    @OptionGroup(title: OptionGroupTitle.experimental) var experimental: ExperimentalOptions
}

@Suite struct OptionGroupsTests {
    @Test func `with no arguments every option has its default`() throws {
        let probe = try Probe.parse([])
        #expect(probe.input.paths == ["."] && probe.input.config == nil && probe.input.excludePaths.isEmpty)
        #expect(
            probe.input.includeRegions == nil && probe.input.excludeRegions == nil && probe.input.deprecations.isEmpty)
        #expect(probe.output.format == .xcode && !probe.output.strict && !probe.output.verbose && !probe.output.quiet)
        #expect(probe.rules.rules == nil)
        #expect(probe.cache.cachePath == nil && !probe.cache.noCache)
        #expect(!probe.index.requested)
        #expect(probe.experimental.embeddings == nil && probe.experimental.deprecations.isEmpty)
    }

    @Test func `the new spellings parse`() throws {
        let probe = try Probe.parse([
            "Sources", "Tests", "--config", "c.json", "--exclude-path", "Generated/", "--exclude-path", "/*.swift",
            "--include-regions", "preview,test", "--exclude-regions", "debug", "--define", "A", "--define", "B",
            "--only", "A.swift", "--only-from", "-", "--format", "sarif", "--relative-to", ".", "--strict",
            "--baseline", "b.json", "--report-new-since", "base.json", "--timings", "--rules", "a,b", "--cache-path",
            "f.json", "--index-store-path", "store", "--experimental-embeddings", "confidence", "--embedding-bundle",
            "m",
        ])
        #expect(probe.input.paths == ["Sources", "Tests"] && probe.input.excludePaths == ["Generated/", "/*.swift"])
        #expect(probe.input.includeRegions == "preview,test" && probe.input.excludeRegions == "debug")
        #expect(probe.input.defines == ["A", "B"] && probe.input.only == ["A.swift"] && probe.input.onlyFrom == "-")
        #expect(probe.output.format == .sarif && probe.output.strict && probe.output.timings)
        #expect(probe.output.reportNewSince == "base.json")
        #expect(probe.rules.rules == ["a", "b"])
        #expect(probe.index.requested && probe.index.indexStorePath == "store")
        #expect(probe.experimental.embeddings == .confidence && probe.experimental.embeddingBundle == "m")
        #expect(probe.input.deprecations.isEmpty && probe.experimental.deprecations.isEmpty)
    }

    @Test func `the old spellings still work and are reported as deprecated`() throws {
        let regions = try Probe.parse(["--include", "preview", "--exclude", "debug"])
        #expect(regions.input.includeRegions == "preview" && regions.input.excludeRegions == "debug")
        #expect(
            regions.input.deprecations == [
                Deprecation(old: "--include", new: "--include-regions"),
                Deprecation(old: "--exclude", new: "--exclude-regions"),
            ])
        let tests = try Probe.parse(["--include-tests"])
        #expect(tests.input.includeRegions == "test,generated")
        #expect(
            tests.input.deprecations == [Deprecation(old: "--include-tests", new: "--include-regions test,generated")])
        let both = try Probe.parse(["--include-regions", "preview", "--include-tests"])
        #expect(both.input.includeRegions == "preview,test,generated")
        let rank = try Probe.parse(["--experimental-embedding-rank"])
        #expect(rank.experimental.embeddings == .rank)
        #expect(
            rank.experimental.deprecations == [
                Deprecation(old: "--experimental-embedding-rank", new: "--experimental-embeddings rank")
            ])
        let confidence = try Probe.parse(["--experimental-embedding-confidence"])
        #expect(confidence.experimental.embeddings == .confidence)
        #expect(
            Deprecation(old: "--include", new: "--include-regions").message(tool: "dolly")
                == "dolly: note: --include is deprecated; use --include-regions")
    }

    @Test func `contradictions are usage errors`() {
        #expect(throws: (any Error).self) { try Probe.parse(["--verbose", "--quiet"]) }
        #expect(throws: (any Error).self) {
            try Probe.parse(["--experimental-embeddings", "rank", "--experimental-embedding-confidence"])
        }
        #expect(throws: (any Error).self) {
            try Probe.parse(["--experimental-embedding-rank", "--experimental-embedding-confidence"])
        }
        #expect(throws: (any Error).self) { try Probe.parse(["--format", "yaml"]) }
    }

    @Test func `help lists the groups in order, every shared option, and no deprecated spelling`() {
        let help = Probe.helpMessage(columns: 120)
        let titles = ["INPUT:", "OUTPUT:", "RULES:", "CACHE:", "INDEX STORE:", "EXPERIMENTAL:"]
        let positions = titles.compactMap { help.firstRange(of: $0)?.lowerBound }
        #expect(positions.count == titles.count && positions == positions.sorted())
        for option in [
            "--config", "--exclude-path", "--include-regions", "--exclude-regions", "--define", "--only", "--only-from",
            "--format", "--relative-to", "--strict", "--baseline", "--write-baseline", "--report-new-since",
            "--verbose",
            "--quiet", "--timings", "--rules", "--cache-path", "--no-cache", "--index-store", "--index-store-path",
            "--index-store-build", "--experimental-embeddings", "--embedding-bundle",
        ] {
            #expect(help.contains(option + " ") || help.contains(option + "\n"), "\(option) missing from help")
        }
        for alias in [
            "--include <", "--exclude <", "--include-tests", "--experimental-embedding-rank",
            "--experimental-embedding-confidence",
        ] {
            #expect(!help.contains(alias), "\(alias) shown in help")
        }
    }

    @Test func `folded region lists are ones every tool's region parser accepts`() throws {
        let probe = try Probe.parse(["--include-regions", "all", "--include-tests", "--exclude", "debug"])
        let selection = try RegionSelection(include: probe.input.includeRegions, exclude: probe.input.excludeRegions)
        #expect(selection.include == CodeRegion.allRegions && selection.exclude == .debugOnly)
        #expect(!selection.isIncluded(.debugOnly) && selection.isIncluded(.test) && selection.isIncluded(.generated))
    }

    /// The shared groups' help, pinned: a changed option name, help text or order shows here first. Regenerate only
    /// for a deliberate surface change (ADR-0019), and say so in the release notes of the five tools.
    @Test func `the shared groups render the recorded help`() throws {
        let golden = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Goldens/help.txt")
        let help = Probe.helpMessage(columns: 120) + "\n"
        if ProcessInfo.processInfo.environment["ANALYZERKIT_RECORD_GOLDENS"] == "1" {
            try Data(help.utf8).write(to: golden)
        }
        let recorded = try String(contentsOf: golden, encoding: .utf8)
        let same = help == recorded
        #expect(same, "help differs from Goldens/help.txt")
    }

}
