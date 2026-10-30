/// A file's lines over its bytes, and conversions between the tools' 1-based UTF-8 columns and the 0-based UTF-16
/// offsets LSP and SARIF count by default (roadmap 0051).
///
/// Lines end at LF, CRLF and CR, as the compiler ends them; a terminator is not part of its line, and a final one
/// starts an empty last line. The index is built in one pass over the bytes, which also marks each line holding a byte
/// outside ASCII, so a conversion on an ASCII line is arithmetic. On other lines the line's bytes are transcoded in
/// place, never copied into a `String`; invalid UTF-8 counts as `String(decoding:as:)` counts it, one replacement
/// character per maximal invalid subsequence.
public struct LineIndex: Sendable {
    private let bytes: [UInt8]
    /// The byte offset each line starts at.
    private let starts: [Int]
    /// The byte offset each line's content ends at, before its terminator.
    private let ends: [Int]
    /// Whether each line holds a byte outside ASCII.
    private let wide: [Bool]

    /// Indexes `bytes`, a file's contents.
    /// - Complexity: O(*n*) in the bytes, one pass.
    public init(_ bytes: [UInt8]) {
        self.bytes = bytes
        var starts = [0]
        var ends: [Int] = []
        var wide: [Bool] = []
        var lineIsWide = false
        do {
            var index = 0
            let count = bytes.count
            while index < count {
                let byte = bytes[index]
                if byte > 0x0D {
                    // Every byte above CR is neither terminator; most are here.
                    if byte >= 0x80 { lineIsWide = true }
                    index += 1
                    continue
                }
                guard byte == 0x0A || byte == 0x0D else {
                    index += 1
                    continue
                }
                ends.append(index)
                wide.append(lineIsWide)
                lineIsWide = false
                index += byte == 0x0D && index + 1 < count && bytes[index + 1] == 0x0A ? 2 : 1
                starts.append(index)
            }
        }
        ends.append(bytes.count)
        wide.append(lineIsWide)
        self.starts = starts
        self.ends = ends
        self.wide = wide
    }

    /// The number of lines; an empty file has one.
    public var lineCount: Int { starts.count }

    /// The length in bytes of 1-based `line` without its terminator, or nil when there is no such line.
    public func length(ofLine line: Int) -> Int? {
        guard line >= 1, line <= starts.count else { return nil }
        return ends[line - 1] - starts[line - 1]
    }

    /// The 1-based line holding the byte at `offset` (a terminator belongs to the line it ends); the end of the file
    /// belongs to the last line. Nil past the end.
    /// - Complexity: O(log *l*) in the lines.
    public func line(containingByte offset: Int) -> Int? {
        guard offset >= 0, offset <= bytes.count else { return nil }
        var low = 0
        var high = starts.count
        while high - low > 1 {
            let middle = (low + high) / 2
            if starts[middle] <= offset { low = middle } else { high = middle }
        }
        return low + 1
    }

    /// The 0-based UTF-16 offset of the 1-based UTF-8 `utf8Column` on 1-based `line`; a column past the end of the line
    /// is clamped to it. Nil when there is no such line.
    /// - Complexity: O(1) on an ASCII line, else O(*c*) in the column.
    public func utf16Offset(line: Int, utf8Column: Int) -> Int? {
        guard let (start, end) = bounds(line) else { return nil }
        let length = min(max(utf8Column - 1, 0), end - start)
        guard wide[line - 1] else { return length }
        var units = 0
        _ = transcode(
            bytes[start..<start + length].makeIterator(), from: UTF8.self, to: UTF16.self, stoppingOnError: false
        ) { _ in units += 1 }
        return units
    }

    /// The 1-based UTF-8 column of the 0-based UTF-16 `utf16Offset` on 1-based `line`; an offset past the end of the
    /// line is clamped to it, and one inside a surrogate pair gives the start of its scalar. Nil when there is no such
    /// line.
    /// - Complexity: O(1) on an ASCII line, else O(*c*) in the column.
    public func utf8Column(line: Int, utf16Offset: Int) -> Int? {
        guard let (start, end) = bounds(line) else { return nil }
        let target = max(utf16Offset, 0)
        guard wide[line - 1] else { return min(target, end - start) + 1 }
        var consumed = 0
        do {
            var iterator = bytes[start..<end].makeIterator()
            var parser = Unicode.UTF8.ForwardParser()
            var units = 0
            scan: while units < target {
                let width: Int
                let length: Int
                switch parser.parseScalar(from: &iterator) {
                case .valid(let encoded):
                    length = encoded.count
                    width = Unicode.UTF8.decode(encoded).value > 0xFFFF ? 2 : 1
                case .error(let errorLength):
                    length = errorLength
                    width = 1
                case .emptyInput:
                    break scan
                }
                guard units + width <= target else { break scan }
                units += width
                consumed += length
            }
        }
        return consumed + 1
    }

    private func bounds(_ line: Int) -> (start: Int, end: Int)? {
        guard line >= 1, line <= starts.count else { return nil }
        return (starts[line - 1], ends[line - 1])
    }
}
