import SourceCorpus
import Testing

/// Line starts and UTF-8 ↔ UTF-16 columns over a file's bytes (roadmap 0051): LSP counts UTF-16 units, the tools
/// count UTF-8 bytes, and the compiler ends a line at LF, CRLF and CR alike.
@Suite struct LineIndexTests {
    private func index(_ text: String) -> LineIndex { LineIndex(Array(text.utf8)) }

    @Test func `LF, CRLF and CR all end a line, and the terminator is not part of it`() {
        let lines = index("a\nbb\r\nccc\rdddd")
        #expect(lines.lineCount == 4)
        #expect((1...4).map { lines.length(ofLine: $0) } == [1, 2, 3, 4])
        #expect(lines.length(ofLine: 0) == nil)
        #expect(lines.length(ofLine: 5) == nil)
    }

    @Test func `a final terminator starts an empty last line, and an empty file has one line`() {
        #expect(index("a\n").lineCount == 2)
        #expect(index("a\n").length(ofLine: 2) == 0)
        #expect(index("").lineCount == 1)
        #expect(index("\r\n\r\n").lineCount == 3)
    }

    @Test func `an ASCII line converts one to one`() {
        let lines = index("let value = 1\n")
        #expect(lines.utf16Offset(line: 1, utf8Column: 1) == 0)
        #expect(lines.utf16Offset(line: 1, utf8Column: 5) == 4)
        #expect(lines.utf8Column(line: 1, utf16Offset: 4) == 5)
    }

    /// `"🙂"` is 4 bytes and 2 UTF-16 units; `"é"` 2 bytes and 1 unit.
    @Test func `a scalar outside the BMP is two UTF-16 units and four bytes`() {
        let lines = index("x\n🙂é = 1\n")
        #expect(lines.utf16Offset(line: 2, utf8Column: 5) == 2)  // after 🙂
        #expect(lines.utf16Offset(line: 2, utf8Column: 7) == 3)  // after é
        #expect(lines.utf8Column(line: 2, utf16Offset: 2) == 5)
        #expect(lines.utf8Column(line: 2, utf16Offset: 3) == 7)
        // An offset inside the surrogate pair gives the scalar's start.
        #expect(lines.utf8Column(line: 2, utf16Offset: 1) == 1)
    }

    @Test func `positions past the end of a line are clamped to it`() {
        let lines = index("ab🙂\r\nnext")
        #expect(lines.utf16Offset(line: 1, utf8Column: 99) == 4)
        #expect(lines.utf8Column(line: 1, utf16Offset: 99) == 7)
        #expect(lines.utf16Offset(line: 3, utf8Column: 1) == nil)
        #expect(lines.utf8Column(line: 0, utf16Offset: 0) == nil)
    }

    /// Invalid UTF-8 counts as `String(decoding:as:)` counts it: each maximal invalid subsequence is one replacement.
    @Test func `invalid UTF-8 counts as String decoding counts it`() {
        let bytes: [UInt8] = [0x61, 0xFF, 0x62, 0xE2, 0x82, 0x63, 0xC3]
        let lines = LineIndex(bytes)
        for column in 1...bytes.count + 1 {
            let expected = String(decoding: bytes[0..<column - 1], as: UTF8.self).utf16.count
            #expect(lines.utf16Offset(line: 1, utf8Column: column) == expected, "column \(column)")
        }
    }

    @Test func `column to offset to column is the identity on every scalar boundary`() {
        let text = "a🙂bé\u{1F468}\u{200D}\u{1F469}c日本"
        let lines = index(text)
        var column = 1
        for scalar in text.unicodeScalars {
            let offset = lines.utf16Offset(line: 1, utf8Column: column)
            #expect(offset.flatMap { lines.utf8Column(line: 1, utf16Offset: $0) } == column, "column \(column)")
            column += String(scalar).utf8.count
        }
        #expect(lines.utf16Offset(line: 1, utf8Column: column) == text.utf16.count)
    }

    @Test func `the line of a byte offset`() {
        let lines = index("a\nbb\r\nccc")
        #expect(lines.line(containingByte: 0) == 1)
        #expect(lines.line(containingByte: 2) == 2)
        #expect(lines.line(containingByte: 6) == 3)
        #expect(lines.line(containingByte: 99) == nil)
    }
}
