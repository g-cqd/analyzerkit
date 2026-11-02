internal import ProjectModel
public import SwiftIfConfig

/// The compiler's `#if` configuration for a target, asked of `swift-frontend -print-static-build-config` (ADR-0030).
public enum CompilerConfiguration {
    /// Why the configuration could not be read.
    public struct Failure: Error, Sendable, Equatable, CustomStringConvertible {
        public let reason: String
        public var description: String { "the compiler's build configuration: \(reason)" }
    }

    /// Runs `frontend -print-static-build-config` for `target` (a triple such as `arm64-apple-ios18.0-simulator`) with
    /// the SDK, the custom conditions and the language mode the target builds with.
    /// - Parameter frontend: the absolute path of `swift-frontend` (`xcrun --find swift-frontend` on macOS).
    public static func read(
        frontend: String,
        target: String,
        sdk: String?,
        defines: [String] = [],
        swiftVersion: String? = nil,
        environment: [String: String]
    ) async throws(Failure) -> StaticBuildConfiguration {
        var arguments = ["-print-static-build-config", "-target", target]
        if let sdk { arguments += ["-sdk", sdk] }
        for define in defines { arguments += ["-D", define] }
        if let swiftVersion { arguments += ["-swift-version", swiftVersion] }
        let result: BoundedProcess.Result
        do {
            result = try await BoundedProcess.run(frontend, arguments, environment: environment, timeout: .seconds(60))
        } catch {
            throw Failure(reason: "\(error)")
        }
        guard result.succeeded else {
            throw Failure(reason: "exit \(result.exitStatus): \(result.standardErrorText.prefix(400))")
        }
        do {
            return try CompilationConditions.compilerConfiguration(json: result.standardOutput)
        } catch {
            throw Failure(reason: "\(error)")
        }
    }
}
