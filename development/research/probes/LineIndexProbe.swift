// Roadmap 0051: LineIndex against swift-search's TextPositions (copied beside it), release build depending on SourceCorpus.

import Dispatch
import SourceCorpus

func best(_ runs: Int, _ body: () -> Void) -> Double {
    var minimum = Double.infinity
    for _ in 0..<runs {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        minimum = min(minimum, Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9)
    }
    return minimum
}
// 10,000 lines of about 40 bytes, every tenth with a non-ASCII scalar, CRLF on every third.
var text = ""
for n in 0..<10_000 {
    text +=
        n % 10 == 0 ? "    let café\(n) = \"🙂 value\" // comment" : "    let value\(n) = compute(\(n), other: \(n * 2))"
    text += n % 3 == 0 ? "\r\n" : "\n"
}
let bytes = Array(text.utf8)
var sink = 0
let build = best(200) { sink &+= LineIndex(bytes).lineCount }
let lines = LineIndex(bytes)
let ascii = best(200) {
    for line in stride(from: 2, through: 10_000, by: 10) { sink &+= lines.utf16Offset(line: line, utf8Column: 30) ?? 0 }
}
let wide = best(200) {
    for line in stride(from: 1, through: 10_000, by: 10) { sink &+= lines.utf16Offset(line: line, utf8Column: 30) ?? 0 }
}
let back = best(200) {
    for line in stride(from: 1, through: 10_000, by: 10) { sink &+= lines.utf8Column(line: line, utf16Offset: 25) ?? 0 }
}
print(
    "bytes \(bytes.count)  index \(String(format: "%.3f", build * 1e3)) ms (\(String(format: "%.2f", Double(bytes.count) / build / 1e9)) GB/s)"
)
print(
    "1,000 conversions: ascii \(String(format: "%.1f", ascii * 1e6)) µs  non-ascii \(String(format: "%.1f", wide * 1e6)) µs  back \(String(format: "%.1f", back * 1e6)) µs  \(sink % 7)"
)
let buildOld = best(50) { sink &+= TextPositions(text).character(line: 1, column: 1, utf16: true) }
let old = TextPositions(text)
let wideOld = best(50) {
    for line in stride(from: 1, through: 10_000, by: 10) { sink &+= old.character(line: line, column: 30, utf16: true) }
}
let backOld = best(50) {
    for line in stride(from: 1, through: 10_000, by: 10) {
        sink &+= old.column(line: line - 1, character: 25, utf16: true)
    }
}
print(
    "TextPositions: index \(String(format: "%.3f", buildOld * 1e3)) ms  1,000 non-ascii \(String(format: "%.1f", wideOld * 1e6)) µs  back \(String(format: "%.1f", backOld * 1e6)) µs"
)
