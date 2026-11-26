extension LineIndex {
    /// The lines of `lines` and `radius` lines on either side, clamped to the file, each as `N: text` and a newline:
    /// what a report or a coding agent reads to see a finding in place without opening the file.
    ///
    /// A line longer than `maxLineBytes` is cut at the last character boundary within it and ends in `…`; invalid
    /// UTF-8 reads as `String(decoding:as:)` reads it. Empty when the span holds no line of the file.
    /// - Complexity: O(*k* · `maxLineBytes`) for the *k* lines printed, at most the file's.
    public func excerpt(lines: ClosedRange<Int>, radius: Int = 2, maxLineBytes: Int = 240) -> String {
        let radius = max(0, min(radius, lineCount))
        let first = max(1, lines.lowerBound.subtractingReportingOverflow(radius).partialValue)
        let last = min(lineCount, lines.upperBound.addingReportingOverflow(radius).partialValue)
        guard first <= last, lines.upperBound >= 1, lines.lowerBound <= lineCount else { return "" }
        var text = ""
        for number in first...last {
            guard let content = content(ofLine: number) else { continue }
            text += "\(number): \(Self.clipped(content, to: max(1, maxLineBytes)))\n"
        }
        return text
    }

    /// `bytes` as text, cut to at most `limit` bytes on a UTF-8 character boundary and marked when cut.
    private static func clipped(_ bytes: ArraySlice<UInt8>, to limit: Int) -> String {
        guard bytes.count > limit else { return String(decoding: bytes, as: UTF8.self) }
        var end = bytes.startIndex + limit
        // Back up over continuation bytes (10xxxxxx) so a multi-byte character is never split.
        while end > bytes.startIndex, bytes[end] & 0xC0 == 0x80 { end -= 1 }
        return String(decoding: bytes[bytes.startIndex..<end], as: UTF8.self) + "…"
    }
}
