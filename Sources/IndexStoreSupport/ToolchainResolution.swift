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
        /// The resolved toolchain's `sourcekit-lsp`, beside the library (`usr/bin` next to `usr/lib`), trusted and
        /// executable; nil when there is no library or the toolchain has no such server (roadmap 0052).
        public let sourceKitLSPPath: String?

        init(libraryPath: String?, diagnostics: [String], sourceKitLSPPath: String? = nil) {
            self.libraryPath = libraryPath
            self.diagnostics = diagnostics
            self.sourceKitLSPPath = sourceKitLSPPath
        }
    }

    /// Why a `sourcekit-lsp` given on the command line is not run.
    public enum SourceKitLSPRejection: Error, Sendable, Equatable, CustomStringConvertible {
        case notAbsolute
        case notExecutable(String)
        case notTrusted(String, reason: String)

        public var description: String {
            switch self {
            case .notAbsolute: "sourcekit-lsp: an explicit path must be absolute"
            case .notExecutable(let path): "sourcekit-lsp: \(path) is not an executable file"
            case .notTrusted(let path, let reason): "sourcekit-lsp: \(path) is not trusted: \(reason)"
            }
        }
    }

    /// An explicit `sourcekit-lsp`: absolute, an executable regular file, and trusted as a library is (ADR-0014). The
    /// path returned is the canonical one that was checked.
    public static func explicitSourceKitLSP(_ path: String) -> Result<String, SourceKitLSPRejection> {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { return .failure(.notAbsolute) }
        let resolved = SourcePath.canonical(path)
        guard isExecutableFile(resolved) else { return .failure(.notExecutable(resolved)) }
        let trust = BinaryTrustChecker.assess(resolved)
        if let reason = trust.rejection { return .failure(.notTrusted(trust.path, reason: reason)) }
        return .success(trust.path)
    }

    /// The `sourcekit-lsp` of the toolchain `library` belongs to, with a diagnostic either way.
    static func sourceKitLSP(besideLibrary library: String) -> (path: String?, diagnostic: String) {
        let usr = URL(fileURLWithPath: library).deletingLastPathComponent().deletingLastPathComponent()
        let candidate = usr.appendingPathComponent("bin/sourcekit-lsp").path
        switch explicitSourceKitLSP(candidate) {
        case .success(let path): return (path, "sourcekit-lsp: selected \(path)")
        case .failure(.notExecutable): return (nil, "sourcekit-lsp: none at \(candidate)")
        case .failure(let rejection): return (nil, rejection.description)
        }
    }

    private static func isExecutableFile(_ path: String) -> Bool {
        var status = stat()
        // SAFETY: path and fixed-size stat storage live for the whole synchronous call; no pointer escapes.
        guard unsafe stat(path, &status) == 0, UInt32(status.st_mode) & UInt32(S_IFMT) == UInt32(S_IFREG) else {
            return false
        }
        return unsafe access(path, X_OK) == 0
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
        func success(_ library: String) -> Outcome {
            let server = sourceKitLSP(besideLibrary: library)
            return Outcome(
                libraryPath: library, diagnostics: diagnostics + [server.diagnostic], sourceKitLSPPath: server.path)
        }
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
