import AnalyzerConfiguration
import Foundation
import Testing

@Suite struct VerboseLinesTests {
    @Test func `verbose names the files read, then each override and each combined exclude`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "verbose-config-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(#"{"exclude": ["a"], "includeRegions": "test", "dolly": {"exclude": ["b"]}}"#.utf8)
            .write(to: root.appending(path: ".swift-analyzers.json"))
        try Data(#"{"includeRegions": "preview"}"#.utf8).write(to: root.appending(path: ".dolly.json"))
        let tool = SharedConfiguration.Tool(name: "dolly", fileName: ".dolly.json", keys: ["rules"])
        let resolved = try SharedConfiguration.resolve(
            for: tool, explicit: nil, currentDirectory: root.path, analyzedPaths: ["."])
        let shared = root.path + "/.swift-analyzers.json"
        #expect(
            resolved.verboseLines(tool: "dolly") == [
                "dolly: configuration: read \(shared), \(shared)#dolly, \(root.path)/.dolly.json",
                "dolly: configuration: exclude combined from \(shared), \(shared)#dolly",
                "dolly: configuration: includeRegions from \(root.path)/.dolly.json, over \(shared)",
            ])
        let none = try SharedConfiguration.resolve(
            for: tool, explicit: nil, currentDirectory: root.appending(path: "empty").path,
            analyzedPaths: [root.appending(path: "empty").path])
        #expect(none.verboseLines(tool: "dolly") == ["dolly: configuration: no file found; built-in defaults"])
    }
}
