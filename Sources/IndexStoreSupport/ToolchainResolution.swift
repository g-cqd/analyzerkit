internal import Foundation
internal import SourceCorpus

#if canImport(Darwin)
    internal import Darwin
#elseif canImport(Glibc)
    internal import Glibc
#endif

/// Filesystem policy for libraries loaded into the analyzer process (ADR-0014).
/// Checks the resolved regular file and its immediate parent, not every ancestor. This is a developer-CLI
/// permission check, not a sandbox or a guarantee against concurrent replacement between checking and dlopen.
public enum BinaryTrustChecker {
    public struct Assessment: Sendable, Equatable {
        public let path: String
        public let rejection: String?
        public var isTrusted: Bool { rejection == nil }
    }

    public static func assess(_ path: String) -> Assessment {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else {
            return Assessment(path: path, rejection: "not an absolute path")
        }
        let resolved = SourcePath.canonical(path)
        func rejected(_ reason: String) -> Assessment { Assessment(path: resolved, rejection: reason) }
        var file = stat()
        // SAFETY: path and fixed-size stat storage live for the whole synchronous call; no pointer escapes.
        guard unsafe lstat(resolved, &file) == 0 else { return rejected("missing or unreadable file") }
        guard UInt32(file.st_mode) & UInt32(S_IFMT) == UInt32(S_IFREG) else { return rejected("not a regular file") }
        guard trustedOwner(file.st_uid, currentUser: getuid()) else {
            return rejected("owner is neither root nor current user")
        }
        guard UInt32(file.st_mode) & 0o022 == 0 else { return rejected("file is group- or world-writable") }
        let parent = URL(fileURLWithPath: resolved).deletingLastPathComponent().path
        var directory = stat()
        guard unsafe lstat(parent, &directory) == 0,
            UInt32(directory.st_mode) & UInt32(S_IFMT) == UInt32(S_IFDIR)
        else { return rejected("missing or unreadable parent directory") }
        guard UInt32(directory.st_mode) & 0o022 == 0 else {
            return rejected("parent directory is group- or world-writable")
        }
        return Assessment(path: resolved, rejection: nil)
    }

    static func trustedOwner(_ owner: UInt32, currentUser: UInt32) -> Bool { owner == 0 || owner == currentUser }

    public static func isTrusted(at path: String) -> Bool { assess(path).isTrusted }
}

/// One ordered resolution policy. Stops at the first trusted candidate, returning its canonical spelling and
/// diagnostics for all attempted candidates. Lower-priority probes are not run after success. No PATH lookup,
/// hard-coded Xcode.app, shell, or project executable is involved.
public enum ToolchainResolution {
    public struct Outcome: Sendable, Equatable {
        public let libraryPath: String?
        public let diagnostics: [String]
    }

    /// Commands are injected for deterministic tests. `xcode-select` reads the system selection without an override;
    /// `xcrun` receives an explicit DEVELOPER_DIR, but never DYLD variables or the caller's PATH.
    public static func resolve(
        environment: [String: String]? = nil,
        home: String? = nil,
        commandLineTools: String = "/Library/Developer/CommandLineTools",
        command: (_ executable: String, _ arguments: [String], _ environment: [String: String]) async -> String? =
            systemProbe
    ) async -> Outcome {
        let environment = environment ?? ProcessInfo.processInfo.environment
        let home = home ?? NSHomeDirectory()
        var diagnostics: [String] = []
        var attempted: Set<String> = []
        func attempt(_ path: String, source: String) -> String? {
            guard attempted.insert(path).inserted else { return nil }
            let assessment = BinaryTrustChecker.assess(path)
            if let reason = assessment.rejection {
                diagnostics.append("libIndexStore: rejected \(source) \(assessment.path): \(reason)")
                return nil
            }
            diagnostics.append("libIndexStore: selected \(source) \(assessment.path)")
            return assessment.path
        }
        func developer(_ path: String, source: String) -> String? {
            let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard path.hasPrefix("/"), !path.utf8.contains(0) else {
                diagnostics.append("libIndexStore: rejected \(source): not an absolute developer directory")
                return nil
            }
            let directory = path.hasSuffix(".app") ? path + "/Contents/Developer" : path
            // xcode-select may select either an Xcode developer directory or Command Line Tools.
            for suffix in [
                "/Toolchains/XcodeDefault.xctoolchain/usr/lib/libIndexStore.dylib", "/usr/lib/libIndexStore.dylib",
            ] {
                if let library = attempt(directory + suffix, source: source) { return library }
            }
            return nil
        }
        func success(_ library: String) -> Outcome { Outcome(libraryPath: library, diagnostics: diagnostics) }
        if let override = environment["DEVELOPER_DIR"], !override.isEmpty,
            let library = developer(override, source: "DEVELOPER_DIR")
        {
            return success(library)
        }

        var safeEnvironment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": home]
        if let selected = await command("/usr/bin/xcode-select", ["-p"], safeEnvironment) {
            if let library = developer(selected, source: "xcode-select") { return success(library) }
        } else {
            diagnostics.append("libIndexStore: xcode-select unavailable or failed")
        }
        if let override = environment["DEVELOPER_DIR"], !override.isEmpty {
            safeEnvironment["DEVELOPER_DIR"] = override
        }
        if let swift = await command("/usr/bin/xcrun", ["--find", "swift"], safeEnvironment)?
            .trimmingCharacters(in: .whitespacesAndNewlines), swift.hasPrefix("/"), !swift.utf8.contains(0)
        {
            let library = URL(fileURLWithPath: swift).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("lib/libIndexStore.dylib").path
            if let library = attempt(library, source: "xcrun") { return success(library) }
        } else {
            diagnostics.append("libIndexStore: xcrun unavailable, failed or returned a non-absolute path")
        }
        let toolchains = URL(fileURLWithPath: home).appendingPathComponent("Library/Developer/Toolchains")
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: toolchains.path)) ?? []
        for entry in entries.sorted(by: >) where entry.hasSuffix(".xctoolchain") {
            let path = toolchains.appendingPathComponent(entry).appendingPathComponent("usr/lib/libIndexStore.dylib")
                .path
            if let library = attempt(path, source: "user toolchain") { return success(library) }
        }
        if let library = attempt(commandLineTools + "/usr/lib/libIndexStore.dylib", source: "Command Line Tools") {
            return success(library)
        }
        diagnostics.append("libIndexStore: no trusted library found")
        return Outcome(libraryPath: nil, diagnostics: diagnostics)
    }

    /// Probes for two small, fixed system commands, with an explicitly scrubbed environment, through ``BoundedProcess``:
    /// ten seconds at most, 4 KiB of output at most. Does not execute the Swift compiler.
    public static func systemProbe(_ executable: String, _ arguments: [String], _ environment: [String: String]) async
        -> String?
    {
        #if os(macOS)
            guard
                (executable == "/usr/bin/xcode-select" && arguments == ["-p"])
                    || (executable == "/usr/bin/xcrun" && arguments == ["--find", "swift"])
            else { return nil }
            var safe = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
            for key in ["HOME", "DEVELOPER_DIR"] { safe[key] = environment[key] }
            guard
                let result = try? await BoundedProcess.run(
                    executable, arguments, environment: safe, timeout: .seconds(10), outputLimit: 4096),
                result.succeeded, !result.outputTruncated
            else { return nil }
            return result.standardOutputText
        #else
            return nil
        #endif
    }
}
