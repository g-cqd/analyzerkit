import Foundation
import ReportSupport
import Testing

/// One model for the four analyzers' SARIF (roadmap 0011): each optional member is omitted when nil, so every tool keeps
/// its bytes, which its goldens pin. These tests pin the model's own encoding.
@Suite struct SarifModelTests {
    private static func encoded(_ log: Sarif.Log) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(log), as: UTF8.self)
    }

    private static func location(_ path: String, root: String?, line: Int, column: Int?) -> Sarif.Location {
        Sarif.Location(
            physicalLocation: Sarif.PhysicalLocation(
                artifactLocation: Sarif.ArtifactLocation(path: path, root: root),
                region: Sarif.Region(startLine: line, startColumn: column)))
    }

    private static let driver = Sarif.Driver(
        name: "t", version: "1", informationUri: "https://example.com",
        rules: [Sarif.Rule(id: "r", shortDescription: Sarif.Text("s"), help: Sarif.Text("h"))])

    @Test func `a minimal run omits every optional member`() throws {
        let result = Sarif.Result(
            ruleId: "r", level: "warning", message: Sarif.Text("m"),
            locations: [Self.location("/abs/A.swift", root: nil, line: 3, column: 5)], partialFingerprints: [:])
        let log = Sarif.Log(runs: [
            Sarif.Run(tool: Sarif.Tool(driver: Self.driver), invocations: nil, root: nil, results: [result])
        ])
        let expected =
            #"{"$schema":"https:\/\/json.schemastore.org\/sarif-2.1.0.json","runs":[{"columnKind":"utf16CodeUnits","#
            + #""results":[{"level":"warning","locations":[{"physicalLocation":{"artifactLocation":{"uri":"#
            + #""file:\/\/\/abs\/A.swift"},"region":{"startColumn":5,"startLine":3}}}],"message":{"text":"m"},"#
            + #""partialFingerprints":{},"ruleId":"r"}],"tool":{"driver":{"informationUri":"https:\/\/example.com","#
            + #""name":"t","rules":[{"help":{"text":"h"},"id":"r","shortDescription":{"text":"s"}}],"version":"1"}}}],"#
            + #""version":"2.1.0"}"#
        #expect(try Self.encoded(log) == expected)
    }

    @Test func `a relative location names SRCROOT, and the run gives its absolute uri`() throws {
        let log = Sarif.Log(runs: [
            Sarif.Run(
                tool: Sarif.Tool(driver: Self.driver), invocations: nil, root: "/repo",
                results: [
                    Sarif.Result(
                        ruleId: "r", level: "note", message: Sarif.Text("m"),
                        locations: [Self.location("Sources/A.swift", root: "/repo", line: 1, column: nil)],
                        partialFingerprints: ["t/v1": "f"])
                ])
        ])
        let text = try Self.encoded(log)
        #expect(text.contains(#""artifactLocation":{"uri":"Sources\/A.swift","uriBaseId":"SRCROOT"}"#))
        #expect(text.contains(#""originalUriBaseIds":{"SRCROOT":{"uri":"file:\/\/\/repo\/"}}"#))
        #expect(text.contains(#""region":{"startLine":1}"#))
        #expect(text.contains(#""partialFingerprints":{"t\/v1":"f"}"#))
    }

    @Test func `related locations, code flows, messages and properties are written when given`() throws {
        let related = Sarif.Location(
            physicalLocation: Self.location("/a/B.swift", root: nil, line: 2, column: 1).physicalLocation,
            message: Sarif.Text("duplicate region"))
        let result = Sarif.Result(
            ruleId: "r", level: "error", message: Sarif.Text("m"),
            locations: [Self.location("/a/A.swift", root: nil, line: 1, column: 1)], relatedLocations: [related],
            codeFlows: [], partialFingerprints: [:], properties: ["confidence": .string("high")])
        let rule = Sarif.Rule(
            id: "r", shortDescription: Sarif.Text("s"), fullDescription: Sarif.Text("f"),
            defaultConfiguration: ["level": "warning"], properties: ["tags": .strings(["security"])])
        let log = Sarif.Log(runs: [
            Sarif.Run(
                tool: Sarif.Tool(driver: Sarif.Driver(name: "t", version: "1", informationUri: "u", rules: [rule])),
                invocations: nil, root: nil, results: [result])
        ])
        let text = try Self.encoded(log)
        #expect(text.contains(#""codeFlows":[]"#))
        #expect(text.contains(#""relatedLocations":[{"message":{"text":"duplicate region"}"#))
        #expect(text.contains(#""properties":{"confidence":"high"}"#))
        #expect(text.contains(#""defaultConfiguration":{"level":"warning"}"#))
        #expect(text.contains(#""fullDescription":{"text":"f"}"#))
        #expect(text.contains(#""properties":{"tags":["security"]}"#))
        #expect(!text.contains("invocations"))
    }

    @Test func `an invocation fails only on a failure, and lists warnings after it`() throws {
        let clean = Sarif.Invocation(failure: nil)
        #expect(clean.executionSuccessful && clean.toolExecutionNotifications == nil)
        let warned = Sarif.Invocation(failure: nil, warnings: ["w"])
        #expect(warned.executionSuccessful)
        #expect(warned.toolExecutionNotifications == [Sarif.Notification(level: "warning", message: Sarif.Text("w"))])
        let failed = Sarif.Invocation(failure: "f", warnings: ["w"])
        #expect(!failed.executionSuccessful)
        #expect(
            failed.toolExecutionNotifications == [
                Sarif.Notification(level: "error", message: Sarif.Text("f")),
                Sarif.Notification(level: "warning", message: Sarif.Text("w")),
            ])
    }
}
