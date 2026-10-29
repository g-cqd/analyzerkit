import AnalyzerConfiguration
import Foundation
import Testing

@Suite struct SharedConfigurationTests {
    private static let arcleak = SharedConfiguration.Tool(
        name: "arcleak", fileName: ".arcleak.json", keys: ["rules", "debugBuild", "contracts"])

    /// A repository root holding `files` (path: contents), resolved through links.
    private func project(_ files: [String: String], _ body: (String) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "shared-config-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        for (path, text) in files.merging(
            [".git": "gitdir: none\n", "Sources/App/A.swift": ""], uniquingKeysWith: { a, _ in a })
        {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        try body(root.path)
    }

    private func resolve(_ root: String, from directory: String = "", explicit: String? = nil)
        throws(SharedConfiguration.Failure)
        -> SharedConfiguration.Resolved
    {
        try SharedConfiguration.resolve(
            for: Self.arcleak, explicit: explicit, currentDirectory: directory.isEmpty ? root : root + "/" + directory,
            analyzedPaths: ["."])
    }

    private func object(_ resolved: SharedConfiguration.Resolved) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(resolved.json)) as? [String: Any])
    }

    @Test func `precedence: shared top level, then the tool's section, then the tool's file`() throws {
        let shared = #"""
            {"exclude": ["Generated/"], "includeRegions": "preview", "excludeRegions": "debug",
             "arcleak": {"exclude": ["/*.swift"], "includeRegions": "test", "rules": {"a": {"enabled": false}, "b": {"severity": "note"}}},
             "deadwood": {"production": true}}
            """#
        let own = #"{"exclude": ["Danger/"], "excludeRegions": "mock", "rules": {"b": {"severity": "error"}}}"#
        try project([".swift-analyzers.json": shared, ".arcleak.json": own]) { root in
            let resolved = try resolve(root)
            let json = try object(resolved)
            #expect(json["exclude"] as? [String] == ["Generated/", "/*.swift", "Danger/"])
            #expect(json["includeRegions"] as? String == "test")
            #expect(json["excludeRegions"] as? String == "mock")
            let rules = try #require(json["rules"] as? [String: [String: Any]])
            #expect(rules["a"]?["enabled"] as? Bool == false)
            #expect(rules["b"]?["severity"] as? String == "error")
            #expect(json["production"] == nil, "another tool's section is not this tool's")
            #expect(resolved.directory == root)
            #expect(
                resolved.sources.map(\.description) == [
                    root + "/.swift-analyzers.json", root + "/.swift-analyzers.json#arcleak", root + "/.arcleak.json",
                ])
            let regions = try #require(resolved.overrides.first { $0.key == "includeRegions" })
            #expect(regions.winner.description == root + "/.swift-analyzers.json#arcleak" && !regions.combined)
            #expect(regions.overridden.map(\.description) == [root + "/.swift-analyzers.json"])
            let exclude = try #require(resolved.overrides.first { $0.key == "exclude" })
            #expect(exclude.combined && exclude.overridden.count == 2)
            #expect(!resolved.overrides.contains { $0.key == "a" })
        }
    }

    @Test func `the current directory wins when it holds a file, else the nearest up to the repository root`() throws {
        try project([
            ".arcleak.json": #"{"exclude": ["root"]}"#, "Sources/.arcleak.json": #"{"exclude": ["here"]}"#,
            "Other/.keep": "",
        ]) { root in
            let here = try object(resolve(root, from: "Sources"))
            #expect(here["exclude"] as? [String] == ["here"])
            let nearest = try resolve(root, from: "Sources/App")
            #expect(try object(nearest)["exclude"] as? [String] == ["here"] && nearest.directory == root + "/Sources")
            let top = try resolve(root, from: "Other")
            #expect(try object(top)["exclude"] as? [String] == ["root"] && top.directory == root)
        }
        try project([".swift-analyzers.json": #"{"exclude": ["shared"]}"#]) { root in
            let shared = try object(resolve(root, from: "Sources/App"))
            #expect(shared["exclude"] as? [String] == ["shared"])
        }
        try project([:]) { root in
            let resolved = try resolve(root)
            #expect(resolved.json == Array("{}".utf8) && resolved.directory == nil && resolved.sources.isEmpty)
        }
    }

    @Test func `no file above the repository root is read, and outside a repository only the current directory`() throws
    {
        let outer = FileManager.default.temporaryDirectory.appending(path: "shared-config-outer-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: outer) }
        let repository = outer.appending(path: "repo")
        let loose = outer.appending(path: "loose/Sources")
        for directory in [repository.appending(path: "Sources"), loose] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data(#"{"exclude": ["outer"]}"#.utf8).write(to: outer.appending(path: ".arcleak.json"))
        try Data("gitdir: none\n".utf8).write(to: repository.appending(path: ".git"))
        let inside = try SharedConfiguration.resolve(
            for: Self.arcleak, explicit: nil, currentDirectory: repository.appending(path: "Sources").path,
            analyzedPaths: ["."])
        #expect(inside.sources.isEmpty, "a configuration above the repository root is not the project's")
        let outside = try SharedConfiguration.resolve(
            for: Self.arcleak, explicit: nil, currentDirectory: loose.path, analyzedPaths: ["."])
        #expect(outside.sources.isEmpty, "outside a repository nothing beyond the current directory is read")
    }

    @Test func `--config names one file, read in the format its name says`() throws {
        try project([
            "config/.swift-analyzers.json": #"{"arcleak": {"exclude": ["a"]}}"#,
            "config/mine.json": #"{"exclude": ["b"]}"#,
            ".arcleak.json": #"{"exclude": ["ignored"]}"#,
        ]) { root in
            let shared = try resolve(root, explicit: "config/.swift-analyzers.json")
            #expect(try object(shared)["exclude"] as? [String] == ["a"])
            #expect(shared.directory == root + "/config")
            let value4 = try object(resolve(root, explicit: root + "/config/mine.json"))
            #expect(value4["exclude"] as? [String] == ["b"])
            #expect(throws: SharedConfiguration.Failure.self) { try resolve(root, explicit: "config/absent.json") }
        }
    }

    @Test func `an unknown key fails, naming the file and the key; another tool's section is not checked`() throws {
        let cases: [(file: String, text: String, key: String)] = [
            (".swift-analyzers.json", #"{"exlude": []}"#, "exlude"),
            (".swift-analyzers.json", #"{"arleak": {}}"#, "arleak"),
            (".swift-analyzers.json", #"{"arcleak": {"bogus": 1}}"#, "arcleak.bogus"),
            (".arcleak.json", #"{"exclude": [], "bogus": {"x": 1}}"#, "bogus"),
        ]
        for item in cases {
            try project([item.file: item.text]) { root in
                #expect(throws: SharedConfiguration.Failure.unknownKey(path: root + "/" + item.file, key: item.key)) {
                    try resolve(root)
                }
            }
        }
        try project([".swift-analyzers.json": #"{"deadwood": {"futureKey": 1}, "fcheck": {"disable": []}}"#]) { root in
            let other = try resolve(root)
            #expect(other.json == Array("{}".utf8))
        }
    }

    @Test func `a malformed file or a shared key of the wrong type fails`() throws {
        for text in [
            "{ broken", "[]", #"{"exclude": "Generated/"}"#, #"{"exclude": [1]}"#, #"{"includeRegions": ["test"]}"#,
            #"{"arcleak": []}"#, #"{"defines": "DEBUG"}"#,
        ] {
            try project([".swift-analyzers.json": text]) { root in
                #expect(throws: SharedConfiguration.Failure.self, "\(text)") { try resolve(root) }
            }
        }
        try project([".arcleak.json": String(repeating: " ", count: 2 << 20) + "{}"]) { root in
            #expect(throws: SharedConfiguration.Failure.self) { try resolve(root) }
        }
    }

    @Test func `a failure gives its reason apart from its path`() {
        #expect(
            SharedConfiguration.Failure.unknownKey(path: "/p/.arcleak.json", key: "bogus").reason
                == #"unknown key "bogus""#)
        #expect(
            SharedConfiguration.Failure.invalid(path: "/p", reason: "not a JSON object").reason == "not a JSON object")
        #expect(SharedConfiguration.Failure.unreadable(path: "/p", reason: "no such file").reason == "no such file")
        #expect(SharedConfiguration.Failure.unknownKey(path: "/p", key: "k").description == #"/p: unknown key "k""#)
    }

    /// A repeated key would keep only its last value, a key silently dropped (ADR-0020 item 4), at any depth.
    @Test func `a key given twice fails, at any depth`() throws {
        for text in [
            #"{"exclude": ["a"], "exclude": ["b"]}"#, #"{"arcleak": {"exclude": ["a"]}, "arcleak": {}}"#,
            #"{"arcleak": {"rules": {"a": {"enabled": true}, "a": {"enabled": false}}}}"#,
        ] {
            try project([".swift-analyzers.json": text]) { root in
                #expect(throws: SharedConfiguration.Failure.self, "\(text)") { try resolve(root) }
            }
        }
        try project([".arcleak.json": #"{"exclude": [], "exclude": ["b"]}"#]) { root in
            #expect(throws: SharedConfiguration.Failure.self) { try resolve(root) }
        }
    }

}
