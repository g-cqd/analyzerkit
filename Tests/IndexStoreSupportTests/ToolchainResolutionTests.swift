import Foundation
import Testing

@testable import IndexStoreSupport

@Suite struct ToolchainResolutionTests {
    private struct Fixture {
        let root: String
        func file(_ path: String, mode: Int = 0o644) throws -> String {
            let url = URL(fileURLWithPath: root + "/" + path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: url.deletingLastPathComponent().path)
            return url.path
        }
        func developer(_ name: String) throws -> String {
            try file(name + "/Toolchains/XcodeDefault.xctoolchain/usr/lib/libIndexStore.dylib")
        }
    }
    private func fixture(_ body: (Fixture) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "toolchain-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        try body(Fixture(root: url.path))
    }

    @Test func `current-user library accepted but unsafe file or parent permissions refused`() throws {
        try fixture { f in
            let path = try f.file("Toolchain/usr/lib/libIndexStore.dylib")
            #expect(BinaryTrustChecker.isTrusted(at: path))
            for mode in [0o664, 0o646] {
                try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
                #expect(!BinaryTrustChecker.isTrusted(at: path))
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
            let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
            for mode in [0o775, 0o757] {
                try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: parent)
                #expect(!BinaryTrustChecker.isTrusted(at: path))
            }
            #expect(!BinaryTrustChecker.isTrusted(at: parent))
            #expect(!BinaryTrustChecker.isTrusted(at: f.root + "/missing"))
            #expect(!BinaryTrustChecker.isTrusted(at: ""))
        }
    }

    @Test func `links resolve before trust and return the checked canonical target`() throws {
        try fixture { f in
            let target = try f.file("real/usr/lib/libIndexStore.dylib")
            let link = f.root + "/linked.dylib"
            try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
            let trusted = BinaryTrustChecker.assess(link)
            #expect(trusted.isTrusted)
            #expect(trusted.path == target)
            try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: target)
            #expect(!BinaryTrustChecker.isTrusted(at: link))
        }
    }

    @Test func `DEVELOPER_DIR wins lazily without consulting subprocesses and accepts an app spelling`() throws {
        try fixture { f in
            let expected = try f.developer("Other Xcode.app/Contents/Developer")
            var commands = 0
            let outcome = ToolchainResolution.resolve(
                environment: ["DEVELOPER_DIR": f.root + "/Other Xcode.app"], home: f.root
            ) { _, _, _ in
                commands += 1; return nil
            }
            #expect(outcome.libraryPath == expected)
            #expect(commands == 0)
            #expect(outcome.diagnostics.contains { $0.contains("DEVELOPER_DIR") && $0.contains(expected) })
        }
    }

    @Test func `rejected override loses to xcode-select and xcrun is later`() throws {
        try fixture { f in
            let rejected = try f.developer("Rejected")
            try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: rejected)
            let selected = try f.developer("Selected")
            var calls: [String] = []
            let outcome = ToolchainResolution.resolve(
                environment: ["DEVELOPER_DIR": f.root + "/Rejected"], home: f.root
            ) {
                executable, args, env in
                calls.append(executable)
                #expect(executable == "/usr/bin/xcode-select")
                #expect(args == ["-p"])
                #expect(env["DEVELOPER_DIR"] == nil)
                return f.root + "/Selected\n"
            }
            #expect(outcome.libraryPath == selected)
            #expect(calls == ["/usr/bin/xcode-select"])
            #expect(outcome.diagnostics.contains { $0.contains(rejected) && $0.contains("writable") })
        }
    }

    @Test func `xcrun precedes reverse-sorted user toolchains and only safe environment reaches it`() throws {
        try fixture { f in
            let expected = try f.file("Active/usr/lib/libIndexStore.dylib")
            _ = try f.file("Library/Developer/Toolchains/z.xctoolchain/usr/lib/libIndexStore.dylib")
            var calls: [String] = []
            let outcome = ToolchainResolution.resolve(
                environment: [
                    "DEVELOPER_DIR": "/missing", "DYLD_INSERT_LIBRARIES": "evil", "PATH": "/evil", "HOME": f.root,
                ], home: f.root
            ) { executable, args, env in
                calls.append(executable)
                #expect(env["DYLD_INSERT_LIBRARIES"] == nil)
                #expect(env["PATH"] == "/usr/bin:/bin:/usr/sbin:/sbin")
                if executable == "/usr/bin/xcode-select" { return nil }
                #expect(args == ["--find", "swift"])
                #expect(env["DEVELOPER_DIR"] == "/missing")
                return f.root + "/Active/usr/bin/swift\n"
            }
            #expect(outcome.libraryPath == expected)
            #expect(calls == ["/usr/bin/xcode-select", "/usr/bin/xcrun"])
        }
    }

    @Test func `user toolchains are deterministic and no trusted candidate is explicit`() throws {
        try fixture { f in
            let a = try f.file("Library/Developer/Toolchains/a.xctoolchain/usr/lib/libIndexStore.dylib")
            let z = try f.file("Library/Developer/Toolchains/z.xctoolchain/usr/lib/libIndexStore.dylib")
            let outcome = ToolchainResolution.resolve(environment: [:], home: f.root) { _, _, _ in nil }
            #expect(outcome.libraryPath == z)
            try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: z)
            #expect(ToolchainResolution.resolve(environment: [:], home: f.root) { _, _, _ in nil }.libraryPath == a)
            // CLT is intentionally last; its machine-specific existence is covered by the candidate-order seam below.
        }
    }
}
