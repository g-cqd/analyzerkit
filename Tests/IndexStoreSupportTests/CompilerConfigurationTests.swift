#if os(macOS)
    import Foundation
    import IndexStoreSupport
    import ProjectModel
    import SwiftIfConfig
    import SwiftSyntax
    import Testing

    /// The compiler's own `#if` configuration for a target (ADR-0030).
    @Suite struct CompilerConfigurationTests {
        private func xcrun(_ arguments: [String]) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            process.waitUntilExit()
            return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        @Test func `the iOS Simulator configuration is the compiler's, and canImport answers from the SDK`()
            async throws
        {
            let frontend = try xcrun(["--find", "swift-frontend"])
            let sdk = try xcrun(["--sdk", "iphonesimulator", "--show-sdk-path"])
            let environment = BoundedProcess.environment(.toolchain, source: ProcessInfo.processInfo.environment)
            let configuration = try await CompilerConfiguration.read(
                frontend: frontend,
                target: "arm64-apple-ios18.0-simulator",
                sdk: sdk,
                defines: ["LITMUS_PROBE"],
                swiftVersion: "6",
                environment: environment
            )
            #expect(configuration.targetOSs.contains("iOS"))
            #expect(configuration.targetEnvironments.contains("simulator"))
            #expect(configuration.customConditions.contains("LITMUS_PROBE"))
            // In Swift 6 mode the compiler reports its own version, which is what `#if swift(>=…)` compares (6.4.2 here).
            #expect(configuration.languageMode.components.first == 6)
            let aware = ModuleAwareBuildConfiguration(
                base: configuration,
                importableModules: CompilationConditions.sdkModules(at: sdk)
            )
            #expect(try aware.canImport(importPath: [(.identifier("UIKit"), "UIKit")], version: .unversioned))
            #expect(try aware.isActiveTargetEnvironment(name: "simulator"))
            #expect(throws: (any Error).self) {
                try aware.canImport(importPath: [(.identifier("AppKit"), "AppKit")], version: .unversioned)
            }
        }
    }
#endif
