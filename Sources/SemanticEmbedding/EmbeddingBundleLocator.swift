public import Foundation

/// Where a tool looks for a Core ML embedding bundle it was shipped with, so a distribution that includes a model uses
/// it with no flag. A plain binary and every dev or test build ship none, which leaves the on-device default in charge.
public enum EmbeddingBundleLocator {
    /// The environment variable that overrides the location, for installs that keep the binary apart from its
    /// resources: `<TOOL>_EMBEDDING_BUNDLE`, the tool's name upper-cased with `-` as `_`.
    public static func environmentVariable(tool: String) -> String {
        tool.uppercased().replacing("-", with: "_") + "_EMBEDDING_BUNDLE"
    }

    /// The bundle next to the running executable, or the one the environment names.
    ///
    /// The executable is `argv[0]` (as `Bundle.main` resolves a command-line tool from it), not `Bundle`: that lives in
    /// corelibs Foundation and would link ICU on Linux.
    public static func directory(tool: String) -> URL? {
        let executable = URL(fileURLWithPath: CommandLine.arguments.first ?? tool).resolvingSymlinksInPath()
        return directory(
            tool: tool,
            executableDirectory: executable.deletingLastPathComponent(),
            override: ProcessInfo.processInfo.environment[environmentVariable(tool: tool)]
        )
    }

    /// The search itself, without process globals. In order: `override`, `<executableDirectory>/Models/MiniLM`, then
    /// `<executableDirectory>/../share/<tool>/Models/MiniLM` (the FHS and Homebrew layout). The first that holds a
    /// `.mlpackage` or `.mlmodelc` wins; `nil` when none does. Each candidate is resolved through symlinks, because
    /// `contentsOfDirectory` does not traverse a URL that is itself a link to a directory.
    public static func directory(tool: String, executableDirectory: URL, override: String?) -> URL? {
        var candidates: [URL] = []
        if let override, !override.isEmpty { candidates.append(URL(fileURLWithPath: override)) }
        candidates.append(executableDirectory.appending(path: "Models/MiniLM"))
        candidates.append(
            executableDirectory.deletingLastPathComponent().appending(path: "share/\(tool)/Models/MiniLM")
        )
        return candidates.map { $0.resolvingSymlinksInPath() }.first(where: holdsModel)
    }

    private static func holdsModel(_ directory: URL) -> Bool {
        guard
            let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return false }
        return contents.contains { $0.pathExtension == "mlpackage" || $0.pathExtension == "mlmodelc" }
    }
}
