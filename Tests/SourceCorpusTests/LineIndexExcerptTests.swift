import SourceCorpus
import Testing

@Suite struct LineIndexExcerptTests {
    private let file = LineIndex(Array("one\ntwo\r\nthree\rfour\nfive\nsix".utf8))

    @Test func `an excerpt numbers the lines around a span, clamped to the file`() {
        #expect(file.excerpt(lines: 3...3, radius: 1) == "2: two\n3: three\n4: four\n")
        #expect(file.excerpt(lines: 1...1, radius: 2) == "1: one\n2: two\n3: three\n")
        #expect(file.excerpt(lines: 5...6, radius: 3) == "2: two\n3: three\n4: four\n5: five\n6: six\n")
        #expect(file.excerpt(lines: 9...9, radius: 1) == "")
        #expect(file.content(ofLine: 2).map { Array($0) } == Array("two".utf8))
        #expect(file.content(ofLine: 0) == nil)
    }

    @Test func `a long line is cut on a character boundary and marked`() {
        let index = LineIndex(Array("é\(String(repeating: "é", count: 10))\n".utf8))
        let excerpt = index.excerpt(lines: 1...1, radius: 0, maxLineBytes: 5)
        #expect(excerpt == "1: éé…\n")
    }

    @Test func `a hostile radius or span stays bounded`() {
        #expect(file.excerpt(lines: 1...Int.max, radius: Int.max).split(separator: "\n").count <= file.lineCount)
        #expect(file.excerpt(lines: -5...0, radius: -1) == "")
    }
}
