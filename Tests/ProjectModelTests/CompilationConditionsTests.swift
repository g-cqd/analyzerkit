import ProjectModel
import SwiftIfConfig
import SwiftParser
import SwiftSyntax
import Testing

/// The active `#if` clauses under `--define` (roadmap 0059): the inactive ones blanked in place, so every line and
/// column of the code that stays is where it was.
@Suite struct CompilationConditionsTests {
    private func active(_ source: String, defines: Set<String>, platforms: Set<String> = []) -> String? {
        let bytes = Array(source.utf8)
        let tree = Parser.parse(source: source)
        return CompilationConditions(defines: defines, platforms: platforms).activeSource(bytes, tree: tree)
            .map { String(decoding: $0, as: UTF8.self) }
    }

    private let source = """
        #if FEATURE
        func leak() { let fd = open("a", 0) }
        #else
        func tidy() { let fd = open("a", 0); close(fd) }
        #endif
        """

    @Test func `the inactive clause is blanked and every byte keeps its offset`() throws {
        let kept = try #require(active(source, defines: ["FEATURE"]))
        #expect(kept.utf8.count == source.utf8.count)
        #expect(kept.split(separator: "\n", omittingEmptySubsequences: false).count == 5)
        #expect(kept.contains("func leak()") && !kept.contains("func tidy()"))
        let other = try #require(active(source, defines: ["OTHER"]))
        #expect(!other.contains("func leak()") && other.contains("func tidy()"))
        #expect(other.contains("#if FEATURE") && other.contains("#endif"))
    }

    @Test func `a statement-level #if in a body follows the same rule, and nested clauses too`() throws {
        let body = """
            func f() {
                #if FEATURE
                    #if os(Linux)
                    linuxOnly()
                    #else
                    elsewhere()
                    #endif
                #else
                    other()
                #endif
            }
            """
        let kept = try #require(active(body, defines: ["FEATURE"], platforms: ["Linux"]))
        #expect(kept.contains("linuxOnly()") && !kept.contains("elsewhere()") && !kept.contains("other()"))
    }

    @Test func `no clause inactive gives nil, so the caller keeps its tree`() {
        #expect(active("func f() {}\n", defines: ["FEATURE"]) == nil)
        #expect(active("#if FEATURE\nfunc f() {}\n#endif\n", defines: ["FEATURE"]) == nil)
    }

    @Test func `the platforms are the os() conditions, the host's when none are given, as arcleak builds them`() {
        let configuration = CompilationConditions(defines: ["A"], platforms: ["macOS"]).buildConfiguration
        #expect(configuration.customConditions == ["A"])
        #expect(configuration.targetOSs == ["macOS", "OSX"])
        #if os(macOS)
            #expect(CompilationConditions(defines: ["A"]).buildConfiguration.targetOSs == ["macOS", "OSX"])
        #endif
    }

    @Test func `without a define nothing is asked`() {
        #expect(!CompilationConditions(defines: [], platforms: ["iOS"]).isRequested)
        #expect(CompilationConditions(defines: ["A"]).isRequested)
    }
}
