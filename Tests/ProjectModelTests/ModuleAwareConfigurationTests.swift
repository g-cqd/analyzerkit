import Foundation
import SwiftIfConfig
import SwiftParser
import SwiftSyntax
import Testing

@testable import ProjectModel

/// `canImport` answered from a module list (ADR-0030).
@Suite struct ModuleAwareConfigurationTests {
    private func activeClauseText(_ source: String, _ configuration: some BuildConfiguration) -> String? {
        let tree = Parser.parse(source: source)
        guard let ifConfig = tree.statements.first?.item.as(IfConfigDeclSyntax.self) else { return nil }
        let clause = ifConfig.activeClause(in: configuration).clause
        return clause?.elements?.trimmedDescription
    }

    private let source = """
        #if canImport(UIKit)
        let ui = 1
        #else
        let other = 2
        #endif
        """

    @Test func `a listed module is importable, an unlisted one is undecided or not importable`() {
        let conditions = CompilationConditions(platforms: ["iOS"])
        #expect(
            activeClauseText(source, conditions.buildConfiguration(importing: ["UIKit", "Foundation"])) == "let ui = 1"
        )
        // Undecided: the condition throws, and SwiftIfConfig counts the clause inactive, as the static configuration did.
        #expect(activeClauseText(source, conditions.buildConfiguration(importing: [])) == "let other = 2")
        #expect(activeClauseText(source, conditions.buildConfiguration) == "let other = 2")
        #expect(
            activeClauseText(source, conditions.buildConfiguration(importing: [], otherModulesImportable: true))
                == "let ui = 1"
        )
        // A version cannot be decided from the list.
        let versioned = "#if canImport(UIKit, _version: 9999)\nlet a = 1\n#else\nlet b = 2\n#endif"
        #expect(activeClauseText(versioned, conditions.buildConfiguration(importing: ["UIKit"])) == "let b = 2")
    }

    @Test func `module maps declare their top-level modules, not their submodules`() {
        let text = """
            module Darwin [system] [extern_c] {
              module C { header "c.h" }
              explicit module Private { }
            }
            framework module Kit {
              umbrella header "Kit.h"
            }
            extern module Outside "outside.modulemap"
            """
        #expect(CompilationConditions.moduleMapModules(text) == ["Darwin", "Kit", "Outside"])
    }

    #if os(macOS)
        @Test func `the SDK's modules include its frameworks, Swift modules and module maps`() throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["--sdk", "iphonesimulator", "--show-sdk-path"]
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            process.waitUntilExit()
            let sdk = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            try #require(process.terminationStatus == 0 && !sdk.isEmpty)
            let modules = CompilationConditions.sdkModules(at: sdk)
            #expect(
                modules.isSuperset(of: ["UIKit", "Foundation", "Swift", "SwiftUI", "Darwin", "XCTest"])
                    || modules.isSuperset(of: ["UIKit", "Foundation", "Swift", "SwiftUI", "Darwin"])
            )
            #expect(!modules.contains("AppKit"))
            #expect(CompilationConditions.sdkModules(at: "/nonexistent").isEmpty)
        }
    #endif
}
