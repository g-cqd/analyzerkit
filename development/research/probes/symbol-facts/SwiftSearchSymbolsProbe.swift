// Roadmap 0055: swift-search's SymbolExtractor over a corpus. Copy into swift-search/Tests/SwiftSearchTests/ and run
// with P55_FILES=<file listing one path per line> P55_OUT=<tsv>; prints the time.
import Foundation
import SwiftSearch
import Testing

@Suite struct P55SwiftSearchProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["P55_FILES"] != nil)) func dump() throws {
        let environment = ProcessInfo.processInfo.environment
        let paths = try String(contentsOfFile: environment["P55_FILES"]!, encoding: .utf8).split(separator: "\n").map(
            String.init)
        let sources = paths.map {
            (path: $0, bytes: Array((try? Data(contentsOf: URL(fileURLWithPath: $0))) ?? Data()))
        }
        var lines: [String] = []
        let started = ContinuousClock.now
        var results: [FileSymbols] = []
        for (path, bytes) in sources { results.append(SymbolExtractor.extract(bytes: bytes, path: path)) }
        let elapsed = ContinuousClock.now - started
        for symbols in results {
            for d in symbols.declarations {
                lines.append("D\t\(symbols.path)\t\(d.line)\t\(d.column)\t\(d.name)\t\(d.kind.rawValue)")
            }
            for r in symbols.references {
                lines.append("R\t\(symbols.path)\t\(r.line)\t\(r.column)\t\(r.name)\t\(r.role.rawValue)")
            }
        }
        try lines.joined(separator: "\n").write(toFile: environment["P55_OUT"]!, atomically: true, encoding: .utf8)
        print("P55 swift-search: \(paths.count) files in \(elapsed)")
    }
}
