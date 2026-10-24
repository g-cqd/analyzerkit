import Foundation
import ReportSupport
import Testing

@Suite struct SarifColumnsTests {
    private func file(_ bytes: [UInt8]) throws -> (path: String, remove: () -> Void) {
        let path = FileManager.default.temporaryDirectory.appending(path: "columns-\(UUID().uuidString).swift").path
        try Data(bytes).write(to: URL(fileURLWithPath: path))
        return (path, { try? FileManager.default.removeItem(atPath: path) })
    }

    private func columns(_ mark: SarifColumns.ByteOrderMark = .parsed) -> SarifColumns {
        SarifColumns(root: nil, byteOrderMark: mark, readCap: 1 << 20)
    }

    @Test func `non-ASCII text before the finding counts in UTF-16 code units`() throws {
        let (path, remove) = try file(Array("let s = \"😀é\"; x\n".utf8))
        defer { remove() }
        var converter = columns()
        // "😀" is 4 bytes and 2 units, "é" is 2 bytes and 1 unit: three columns fewer.
        #expect(converter.column(18, line: 1, path: path) == 15)
        #expect(converter.column(1, line: 1, path: path) == 1)
    }

    @Test func `lines break at LF, CRLF and a lone CR, as swift-syntax breaks them`() throws {
        let (path, remove) = try file(Array("a\r\nb\rcé x\n".utf8))
        defer { remove() }
        var converter = columns()
        #expect(converter.column(5, line: 3, path: path) == 4, "line 3 is `cé x`: the byte column of `x` is 5")
        #expect(converter.column(3, line: 2, path: path) == 3)
    }

    @Test func `a parsed byte-order mark is in line 1's byte columns and is taken out`() throws {
        let (path, remove) = try file([0xEF, 0xBB, 0xBF] + Array("xy\n".utf8))
        defer { remove() }
        var converter = columns(.parsed)
        // swift-syntax saw the mark: `x` is at byte column 4 and `y` at 5; the editor's columns are 1 and 2.
        #expect(converter.column(5, line: 1, path: path) == 2)
        #expect(converter.column(4, line: 1, path: path) == 1)
    }

    @Test func `a dropped byte-order mark starts line 1 after it, and later lines are unaffected`() throws {
        let (path, remove) = try file([0xEF, 0xBB, 0xBF] + Array("xé\nab\n".utf8))
        defer { remove() }
        var converter = columns(.dropped)
        #expect(converter.column(4, line: 1, path: path) == 3, "`é` is two bytes and one unit")
        #expect(converter.column(2, line: 2, path: path) == 2)
    }

    @Test func `a file that cannot be read keeps its byte column`() {
        var converter = columns()
        #expect(converter.column(9, line: 3, path: "/nonexistent/A.swift") == 9)
    }

    @Test func `a column past the end of its line is returned unchanged`() throws {
        let (path, remove) = try file(Array("ab\ncd\n".utf8))
        defer { remove() }
        var converter = columns()
        #expect(converter.column(50, line: 1, path: path) == 50)
    }

    @Test func `relative paths resolve against the root`() throws {
        let (path, remove) = try file(Array("é x\n".utf8))
        defer { remove() }
        let url = URL(fileURLWithPath: path)
        var converter = SarifColumns(
            root: url.deletingLastPathComponent().path, byteOrderMark: .parsed, readCap: 1 << 20)
        #expect(converter.column(4, line: 1, path: url.lastPathComponent) == 3)
    }
}
