import ProjectModel
import SwiftParser
import SwiftSyntax
import Testing

@Suite struct CodeRegionScannerTests {
    private func spans(_ source: String) -> [RegionSpan] {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: "Sample.swift", tree: tree)
        return CodeRegionScanner.scan(tree, converter: converter)
    }

    @Test func `debug clauses, previews and preview providers are regions`() {
        let found = spans(
            """
            struct SampleView {
                func render() {
                    #if DEBUG
                    print("debug")
                    #endif
                }
            }

            #Preview {
                SampleView()
            }

            struct SampleView_Previews: PreviewProvider {
                static var previews: some View { SampleView() }
            }
            """
        )

        #expect(
            found == [
                RegionSpan(startLine: 3, endLine: 4, region: .debugOnly),
                RegionSpan(startLine: 9, endLine: 11, region: .preview),
                RegionSpan(startLine: 13, endLine: 15, region: .preview),
            ]
        )
    }

    @Test func `a line's region is the union of the spans holding it`() {
        let found = spans(
            """
            #if DEBUG
            #Preview {
                SampleView()
            }
            #endif
            """
        )

        #expect(RegionSpan.region(atLine: 3, in: found) == [.debugOnly, .preview])
        #expect(RegionSpan.region(atLine: 6, in: found) == .production)
    }

    /// A site on a line shared with a preview, outside its bytes, stays production (ADR-0030).
    @Test func `byte ranges tell a site beside a region from one inside it`() throws {
        let source = "let a = 1; #Preview { SampleView() }\n"
        let found = spans(source)
        let preview = try #require(found.first)
        let bytes = try #require(preview.bytes)
        #expect(
            String(
                source.utf8[
                    source.utf8.index(
                        source.utf8.startIndex,
                        offsetBy: bytes.lowerBound
                    )..<source.utf8.index(source.utf8.startIndex, offsetBy: bytes.upperBound)
                ]
            ) == "#Preview { SampleView() }"
        )
        #expect(RegionSpan.region(atByte: 4, line: 1, in: found) == .production)
        #expect(RegionSpan.region(atByte: bytes.lowerBound + 2, line: 1, in: found) == .preview)
        #expect(RegionSpan.region(atLine: 1, in: found) == .preview)
        // A span without bytes is decided by its lines.
        #expect(
            RegionSpan.region(atByte: 4, line: 1, in: [RegionSpan(startLine: 1, endLine: 1, region: .preview)])
                == .preview
        )
    }
}
