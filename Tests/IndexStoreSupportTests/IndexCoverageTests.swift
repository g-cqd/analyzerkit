import Foundation
import IndexStoreSupport
import ReportSupport
import Testing

/// ADR-0005 items 1 and 2: each analyzed file is classified against the store, and a store that indexes none of them is
/// not used at all.
@Suite struct IndexCoverageTests {
    private let built = Date(timeIntervalSince1970: 1_000)
    private let before = Date(timeIntervalSince1970: 900)
    private let after = Date(timeIntervalSince1970: 1_100)

    /// `Indexed.swift` unchanged since its unit; `Edited.swift` changed after; `New.swift` never built; `Locked.swift`
    /// with no readable modification time.
    private func classify(_ files: [String]) -> IndexCoverage {
        let units: [String: Date] = ["/p/Indexed.swift": built, "/p/Edited.swift": built, "/p/Locked.swift": built]
        let modified: [String: Date] = ["/p/Indexed.swift": before, "/p/Edited.swift": after, "/p/New.swift": before]
        return IndexCoverage.classify(files, unitDate: { units[$0] }, modificationDate: { modified[$0] })
    }

    @Test func `each file is indexed, not indexed, changed since the build, or unreadable`() {
        let coverage = classify(["/p/Indexed.swift", "/p/Edited.swift", "/p/New.swift", "/p/Locked.swift"])
        #expect(coverage.files.map(\.coverage) == [.indexed, .changedSinceBuild, .notIndexed, .unreadable])
        #expect(coverage.paths(.indexed) == ["/p/Indexed.swift"])
        #expect(coverage.paths(.notIndexed) == ["/p/New.swift"])
        #expect(coverage.isUsable)
        let skipped: [SkippedFile] = [
            SkippedFile(path: "/p/Edited.swift", reason: .changedSinceBuild),
            SkippedFile(path: "/p/New.swift", reason: .notIndexed),
            SkippedFile(path: "/p/Locked.swift", reason: .unreadable),
        ]
        #expect(coverage.skippedFiles == skipped)
    }

    @Test func `a file saved in the second its unit was written counts as indexed`() {
        let coverage = IndexCoverage.classify(
            ["/p/Same.swift"], unitDate: { _ in Date(timeIntervalSince1970: 1_000) },
            modificationDate: { _ in Date(timeIntervalSince1970: 1_000) })
        #expect(coverage.files.map(\.coverage) == [.indexed])
    }

    @Test func `a store that indexes none of the files is not used, and one note says why`() {
        let coverage = classify(["/p/New.swift", "/p/Edited.swift"])
        #expect(!coverage.isUsable)
        let notes = coverage.runNotes(store: "/s/DataStore", verbose: false)
        #expect(notes.map(\.code) == ["index-not-used"])
        #expect(notes.first?.severity == "warning")
        #expect(notes.first?.message.contains("/s/DataStore") == true)
        #expect(notes.first?.message.contains("none of the 2 analyzed files") == true)
    }

    @Test func `a partly covering store says which files it does not cover, by class`() throws {
        let coverage = classify(["/p/Indexed.swift", "/p/Edited.swift", "/p/New.swift", "/p/Locked.swift"])
        let notes = coverage.runNotes(store: "/s/DataStore", verbose: false)
        try #require(notes.map(\.code) == ["index-changed-since-build", "index-not-indexed", "index-unreadable"])
        #expect(notes.map(\.severity) == ["note", "note", "warning"])
        #expect(notes.map(\.paths) == [["/p/Edited.swift"], ["/p/New.swift"], ["/p/Locked.swift"]])
        #expect(notes[0].message.contains("rebuild"))
        #expect(notes[1].message.contains("not built by this scheme"))
    }

    @Test func `a fully covering store has nothing to say`() {
        let coverage = classify(["/p/Indexed.swift"])
        #expect(coverage.runNotes(store: "/s/DataStore", verbose: false).isEmpty)
        #expect(coverage.skippedFiles.isEmpty)
    }
}
