import Foundation
import Testing

@testable import IndexStoreSupport

/// The toolchain's sourcekit-lsp, found beside the library it resolves (roadmap 0052): the server and the index reader
/// always come from one toolchain, and finding the server costs no command of its own.
@Suite struct SourceKitLSPResolutionTests {
    private struct Toolchain {
        let root: String
        @discardableResult
        func file(_ path: String, mode: Int) throws -> String {
            let url = URL(fileURLWithPath: root + "/" + path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: url.deletingLastPathComponent().path)
            return url.path
        }
        var usr: String { "Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr" }
    }

    private func toolchain(_ body: (Toolchain) async throws -> Void) async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "sklsp-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        try await body(Toolchain(root: url.path))
    }

    @Test func `the server is found beside the library, with no command run`() async throws {
        try await toolchain { t in
            let library = try t.file(t.usr + "/lib/libIndexStore.dylib", mode: 0o644)
            let server = try t.file(t.usr + "/bin/sourcekit-lsp", mode: 0o755)
            var commands = 0
            let outcome = await ToolchainResolution.resolve(
                environment: ["DEVELOPER_DIR": t.root + "/Xcode.app"], home: t.root
            ) { _, _, _ in
                commands += 1
                return nil
            }
            #expect(outcome.libraryPath == library)
            #expect(outcome.sourceKitLSPPath == server)
            #expect(commands == 0)
        }
    }

    @Test func `a toolchain without the server keeps its library and says what is missing`() async throws {
        try await toolchain { t in
            let library = try t.file(t.usr + "/lib/libIndexStore.dylib", mode: 0o644)
            let outcome = await ToolchainResolution.resolve(
                environment: ["DEVELOPER_DIR": t.root + "/Xcode.app"], home: t.root
            ) { _, _, _ in nil }
            #expect(outcome.libraryPath == library)
            #expect(outcome.sourceKitLSPPath == nil)
            #expect(outcome.diagnostics.contains { $0.hasPrefix("sourcekit-lsp:") && $0.contains("bin/sourcekit-lsp") })
        }
    }

    @Test func `a server that is not executable or is writable by others is refused`() async throws {
        try await toolchain { t in
            try t.file(t.usr + "/lib/libIndexStore.dylib", mode: 0o644)
            let server = try t.file(t.usr + "/bin/sourcekit-lsp", mode: 0o644)
            for mode in [0o644, 0o775] {
                try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: server)
                let outcome = await ToolchainResolution.resolve(
                    environment: ["DEVELOPER_DIR": t.root + "/Xcode.app"], home: t.root
                ) { _, _, _ in nil }
                #expect(outcome.sourceKitLSPPath == nil, "mode \(String(mode, radix: 8))")
            }
        }
    }

    @Test func `xcrun is asked once, for the compiler, and the server comes from its toolchain`() async throws {
        try await toolchain { t in
            let library = try t.file("Custom.xctoolchain/usr/lib/libIndexStore.dylib", mode: 0o644)
            let server = try t.file("Custom.xctoolchain/usr/bin/sourcekit-lsp", mode: 0o755)
            var asked: [[String]] = []
            let outcome = await ToolchainResolution.resolve(environment: [:], home: t.root + "/nowhere") {
                executable, arguments, _ in
                asked.append([executable] + arguments)
                return executable == "/usr/bin/xcrun" ? t.root + "/Custom.xctoolchain/usr/bin/swift\n" : nil
            }
            #expect(outcome.libraryPath == library)
            #expect(outcome.sourceKitLSPPath == server)
            #expect(asked.filter { $0.first == "/usr/bin/xcrun" } == [["/usr/bin/xcrun", "--find", "swift"]])
        }
    }

    @Test func `an explicit server must be absolute, executable and trusted`() async throws {
        try await toolchain { t in
            let server = try t.file("bin/sourcekit-lsp", mode: 0o755)
            #expect(ToolchainResolution.explicitSourceKitLSP(server) == .success(server))
            #expect(ToolchainResolution.explicitSourceKitLSP("bin/sourcekit-lsp") == .failure(.notAbsolute))
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: server)
            #expect(ToolchainResolution.explicitSourceKitLSP(server) == .failure(.notExecutable(server)))
            try FileManager.default.setAttributes([.posixPermissions: 0o757], ofItemAtPath: server)
            guard case .failure(.notTrusted(let path, _)) = ToolchainResolution.explicitSourceKitLSP(server) else {
                Issue.record("a world-writable server was accepted")
                return
            }
            #expect(path == server)
        }
    }
}
