internal import SourceCorpus

/// Converts an analyzer's columns to the unit SARIF regions count in.
///
/// Findings carry swift-syntax's columns: 1-based UTF-8 byte offsets into the line. They stay that way everywhere
/// else, since the fingerprint hashes them and compilers print byte columns too, but a SARIF run declares its
/// `columnKind`, and the one consumers assume is `utf16CodeUnits` (SARIF 2.1.0 §3.14.27), the unit editors index
/// lines in. On a line with non-ASCII text before a finding, a byte column lands to the right of it: after `"😀é"`
/// it is three columns off.
///
/// A byte-order mark does not count (SARIF 2.1.0 §3.30.2). What the parser saw decides how: see
/// ``ByteOrderMark``.
///
/// Each file is read once, capped like the analyzer's own reads. A file that can no longer be read keeps its byte
/// column, which is exact whenever the text before it is ASCII.
public struct SarifColumns {
    /// Whether the text the analyzer handed swift-syntax still had the file's byte-order mark.
    public enum ByteOrderMark: Sendable {
        /// The mark was parsed, so the byte columns of line 1 count it and the conversion takes it out.
        case parsed
        /// The analyzer's decode dropped the mark before parsing, so line 1 starts after it and no column counts it.
        case dropped
    }

    /// A file's bytes, and the offset each of its lines starts at.
    private struct Text {
        let bytes: [UInt8]
        let lineStarts: [Int]
    }

    private static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// Where relative report paths resolve; nil when every path is absolute.
    private let root: String?
    private let mark: ByteOrderMark
    private let readCap: Int
    /// Each file read so far, or nil when it could not be.
    private var texts: [String: Text?] = [:]

    /// - Parameters:
    ///   - root: where relative report paths resolve, or nil when every path is absolute.
    ///   - byteOrderMark: what the analyzer's parse did with a byte-order mark.
    ///   - readCap: the largest file read, in bytes.
    public init(root: String?, byteOrderMark: ByteOrderMark, readCap: Int) {
        self.root = root
        self.mark = byteOrderMark
        self.readCap = readCap
    }

    /// `column`, a UTF-8 column on `line` of `path`, in UTF-16 code units.
    /// - Complexity: O(*c*) in the column, after one O(*n*) read of the file.
    public mutating func column(_ column: Int, line: Int, path: String) -> Int {
        guard column > 1, line >= 1, let text = text(of: path), line <= text.lineStarts.count else {
            return column
        }
        let start = text.lineStarts[line - 1]
        let lineEnd = line < text.lineStarts.count ? text.lineStarts[line] : text.bytes.count
        let end = start + column - 1
        guard end <= lineEnd else { return column }
        var before = text.bytes[start..<end]
        if mark == .parsed, start == 0, before.starts(with: Self.byteOrderMark) {
            before = before.dropFirst(Self.byteOrderMark.count)
        }
        return String(decoding: before, as: UTF8.self).utf16.count + 1
    }

    private mutating func text(of path: String) -> Text? {
        if let cached = texts[path] { return cached }
        let resolved: String
        if path.hasPrefix("/") {
            resolved = path
        } else if let root {
            resolved = root.hasSuffix("/") ? root + path : root + "/" + path
        } else {
            resolved = path
        }
        let text = (try? BoundedFileReader.read(path: resolved, cap: readCap)).map {
            Text(bytes: $0, lineStarts: lineStarts(of: $0))
        }
        texts[path] = text
        return text
    }

    /// Where each line starts, breaking lines where swift-syntax does: at `\n`, `\r\n` and a lone `\r`.
    private func lineStarts(of bytes: [UInt8]) -> [Int] {
        let first = mark == .dropped && bytes.starts(with: Self.byteOrderMark) ? Self.byteOrderMark.count : 0
        var starts = [first]
        var index = first
        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "\r"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "\n") {
                index += 1
            }
            if bytes[index] == UInt8(ascii: "\n") || bytes[index] == UInt8(ascii: "\r") {
                starts.append(index + 1)
            }
            index += 1
        }
        return starts
    }
}
