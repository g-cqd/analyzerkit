import ReportSupport
import Testing

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

private struct Item: Equatable {
    let id: String
    let anchor: AcceptanceFile.Anchor
}

private func entry(
    _ id: String,
    path: String = "Sources/A/Policy.swift",
    declaration: String = "Policy.remaining(_:_:)",
    rule: String = "replace-relational",
    text: String = "available > reserved",
    replacement: String? = "available >= reserved",
    reason: String = "equal operands give 0 on both branches"
) -> AcceptanceFile.Entry {
    AcceptanceFile.Entry(
        id: id,
        path: path,
        declaration: declaration,
        rule: rule,
        text: text,
        replacement: replacement,
        reason: reason,
        addedAt: "2026-11-27"
    )
}

@Suite struct AcceptanceFileTests {
    @Test func `entries are written sorted by path, declaration, rule and id, and read back equal`() throws {
        let file = try AcceptanceFile(tool: "litmus")
            .adding(entry("b2", path: "Sources/B.swift"))
            .adding(entry("a1"))
            .adding(entry("a0", rule: "negate-condition"))
        #expect(file.accepted.map(\.id) == ["a0", "a1", "b2"])
        let data = try file.encoded()
        #expect(try AcceptanceFile.decode(data, tool: "litmus") == file)
        // Deterministic bytes: the same set always writes the same file.
        #expect(
            try AcceptanceFile(tool: "litmus").adding(entry("a0", rule: "negate-condition")).adding(entry("a1"))
                .adding(entry("b2", path: "Sources/B.swift")).encoded() == data
        )
    }

    @Test func `adding an id again replaces its entry; removing reports whether it was there`() throws {
        let file = try AcceptanceFile(tool: "t").adding(entry("a1")).adding(
            entry("a1", reason: "a better ten-plus reason")
        )
        #expect(file.accepted.count == 1 && file.accepted[0].reason == "a better ten-plus reason")
        let (removed, found) = file.removing(id: "a1")
        #expect(found && removed.accepted.isEmpty)
        #expect(!file.removing(id: "zz").found)
    }

    @Test(arguments: ["", "ok", "   short    ", "fine\n\n\t"])
    func `a reason shorter than ten non-whitespace characters is refused`(reason: String) {
        #expect(throws: AcceptanceFile.Failure.reasonTooShort(id: "a1")) {
            try AcceptanceFile(tool: "t").adding(entry("a1", reason: reason))
        }
    }

    @Test func `a file of another version, another tool, a repeated id or a weak reason is refused whole`() throws {
        func bytes(_ json: String) -> Data { Data(json.utf8) }
        #expect(throws: AcceptanceFile.Failure.unsupportedVersion(2)) {
            try AcceptanceFile.decode(bytes(#"{"schemaVersion":2,"tool":"t","accepted":[]}"#), tool: "t")
        }
        #expect(throws: AcceptanceFile.Failure.otherTool("u")) {
            try AcceptanceFile.decode(bytes(#"{"schemaVersion":1,"tool":"u","accepted":[]}"#), tool: "t")
        }
        let one = entryJSON("a1", reason: "equal operands give 0 on both branches")
        let doubled = #"{"schemaVersion":1,"tool":"t","accepted":["# + one + "," + one + "]}"
        #expect(throws: AcceptanceFile.Failure.duplicateID("a1")) {
            try AcceptanceFile.decode(bytes(doubled), tool: "t")
        }
        let weak = #"{"schemaVersion":1,"tool":"t","accepted":["# + entryJSON("a1", reason: "ok") + "]}"
        #expect(throws: AcceptanceFile.Failure.reasonTooShort(id: "a1")) {
            try AcceptanceFile.decode(bytes(weak), tool: "t")
        }
        #expect(throws: AcceptanceFile.Failure.self) { try AcceptanceFile.decode(bytes("{"), tool: "t") }
    }

    @Test func `findings match by id, then by an unambiguous anchor; unmatched entries are stale`() throws {
        let file = try AcceptanceFile(tool: "t")
            .adding(entry("a1"))
            .adding(entry("moved", text: "x  <  y", replacement: "x <= y"))
            .adding(entry("gone", text: "deleted code"))
        let byID = Item(id: "a1", anchor: entry("a1").anchor)
        // Its ordinal shifted, so its id changed; the anchor (whitespace-insensitive) still finds it.
        let renumbered = Item(id: "new-id", anchor: entry("x", text: "x < y", replacement: "x <= y").anchor)
        let other = Item(id: "o", anchor: entry("o", text: "something else").anchor)
        let matches = file.match([byID, renumbered, other], id: \.id, anchor: \.anchor)
        #expect(matches.accepted.map(\.item) == [byID, renumbered])
        #expect(matches.accepted.map(\.entry.id) == ["a1", "moved"])
        #expect(matches.remaining == [other])
        #expect(matches.stale.map(\.id) == ["gone"])
    }

    @Test func `an anchor matching two findings accepts neither`() throws {
        let file = try AcceptanceFile(tool: "t").adding(entry("old", text: "a > b"))
        let twins = [
            Item(id: "x1", anchor: entry("x1", text: "a > b").anchor),
            Item(id: "x2", anchor: entry("x2", text: "a > b").anchor),
        ]
        let matches = file.match(twins, id: \.id, anchor: \.anchor)
        #expect(matches.accepted.isEmpty && matches.remaining == twins && matches.stale.map(\.id) == ["old"])
    }
}

private func entryJSON(_ id: String, reason: String) -> String {
    let data = (try? JSONEncoder().encode(entry(id, reason: reason))) ?? Data()
    return String(decoding: data, as: UTF8.self)
}
