// Roadmap 0055: deadwood's DeclarationCollector and ReferenceCollector over a corpus. Copy into
// deadwood/Tests/DeadwoodCoreTests/ and run with P55_FILES=<file listing one path per line> P55_OUT=<tsv>.
import Foundation
import SwiftParser
import SwiftSyntax
import Testing

@testable import DeadwoodCore

@Suite struct P55DeadwoodProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["P55_FILES"] != nil)) func dump() throws {
        let environment = ProcessInfo.processInfo.environment
        let paths = try String(contentsOfFile: environment["P55_FILES"]!, encoding: .utf8).split(separator: "\n").map(
            String.init)
        let sources = paths.map {
            (path: $0, bytes: Array((try? Data(contentsOf: URL(fileURLWithPath: $0))) ?? Data()))
        }
        var lines: [String] = []
        let started = ContinuousClock.now
        var results: [FileAnalysisResult] = []
        let analyzer = StaticAnalyzer()
        for (path, bytes) in sources {
            let tree = Parser.parse(source: String(decoding: bytes, as: UTF8.self))
            let converter = SourceLocationConverter(fileName: path, tree: tree)
            results.append(analyzer.collectFacts(tree: tree, file: path, converter: converter))
        }
        let elapsed = ContinuousClock.now - started
        for result in results {
            for d in result.declarations {
                lines.append(
                    "D\t\(result.file)\t\(d.location.line)\t\(d.location.column)\t\(d.name)\t\(d.kind.rawValue)")
            }
            for r in result.references {
                lines.append(
                    "R\t\(result.file)\t\(r.location.line)\t\(r.location.column)\t\(r.identifier)\t\(r.context.rawValue)"
                )
            }
        }
        try lines.joined(separator: "\n").write(toFile: environment["P55_OUT"]!, atomically: true, encoding: .utf8)
        print("P55 deadwood: \(paths.count) files in \(elapsed)")
    }
}
