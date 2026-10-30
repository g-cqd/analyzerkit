import Foundation
import IndexStoreSupport
import Synchronization
import Testing

/// Freshness decided once per file for a session's life (roadmap 0053, ADR-0005): swift-search asked the database and the
/// file system again for every match and every use (its H3).
extension IndexCoverage {
    static let none = IndexCoverage.classify([], unitDate: { _ in nil }, modificationDate: { _ in nil })
}

@Suite struct IndexFreshnessTests {
    /// Counts the lookups a freshness check makes.
    final class Probe: Sendable {
        let units = Mutex(0)
        let stats = Mutex(0)
        let built: Date
        let modified: Mutex<[String: Date]>

        init(files: [String], built: Date = Date(timeIntervalSince1970: 1_000), modified: Date) {
            self.built = built
            self.modified = Mutex(Dictionary(uniqueKeysWithValues: files.map { ($0, modified) }))
        }

        var unitDate: @Sendable (String) -> Date? {
            { [self] file in
                units.withLock { $0 += 1 }
                return file.hasPrefix("/missing") ? nil : built
            }
        }

        var modificationDate: @Sendable (String) -> Date? {
            { [self] file in
                stats.withLock { $0 += 1 }
                return modified.withLock { $0[file] }
            }
        }
    }

    @Test func `a thousand questions on ten files cost ten lookups`() {
        let files = (0..<10).map { "/p/F\($0).swift" }
        let probe = Probe(files: files, modified: Date(timeIntervalSince1970: 500))
        let freshness = IndexFreshness(
            coverage: IndexCoverage.none, unitDate: probe.unitDate, modificationDate: probe.modificationDate)
        for round in 0..<100 {
            for file in files { #expect(freshness.isCurrent(file), "round \(round)") }
        }
        #expect(probe.units.withLock { $0 } == 10)
        #expect(probe.stats.withLock { $0 } == 10)
    }

    @Test func `the files classified when the store opened cost no lookup`() {
        let coverage = IndexCoverage.classify(
            ["/p/A.swift", "/p/B.swift"], unitDate: { _ in Date(timeIntervalSince1970: 1_000) },
            modificationDate: {
                $0.hasSuffix("A.swift") ? Date(timeIntervalSince1970: 500) : Date(timeIntervalSince1970: 2_000)
            })
        let probe = Probe(files: [], modified: Date())
        let freshness = IndexFreshness(
            coverage: coverage, unitDate: probe.unitDate, modificationDate: probe.modificationDate)
        #expect(freshness.isCurrent("/p/A.swift"))
        #expect(!freshness.isCurrent("/p/B.swift"))
        #expect(probe.units.withLock { $0 } == 0)
        #expect(probe.stats.withLock { $0 } == 0)
    }

    @Test func `a file with no unit, changed after its unit or unreadable is not current`() {
        let probe = Probe(files: ["/p/New.swift"], modified: Date(timeIntervalSince1970: 2_000))
        let freshness = IndexFreshness(
            coverage: IndexCoverage.none, unitDate: probe.unitDate, modificationDate: probe.modificationDate)
        #expect(!freshness.isCurrent("/missing/A.swift"))
        #expect(!freshness.isCurrent("/p/New.swift"))
        #expect(!freshness.isCurrent("/p/Gone.swift"))
    }

    /// A session is a snapshot: a file edited after the first answer keeps it; a new session sees the edit.
    @Test func `an answer holds for the session and a new one sees the change`() {
        let probe = Probe(files: ["/p/A.swift"], modified: Date(timeIntervalSince1970: 500))
        let first = IndexFreshness(
            coverage: IndexCoverage.none, unitDate: probe.unitDate, modificationDate: probe.modificationDate)
        #expect(first.isCurrent("/p/A.swift"))
        probe.modified.withLock { $0["/p/A.swift"] = Date(timeIntervalSince1970: 2_000) }
        #expect(first.isCurrent("/p/A.swift"))
        let second = IndexFreshness(
            coverage: IndexCoverage.none, unitDate: probe.unitDate, modificationDate: probe.modificationDate)
        #expect(!second.isCurrent("/p/A.swift"))
    }

    @Test func `concurrent questions agree`() async {
        let files = (0..<50).map { "/p/F\($0).swift" }
        let probe = Probe(files: files, modified: Date(timeIntervalSince1970: 500))
        let freshness = IndexFreshness(
            coverage: IndexCoverage.none, unitDate: probe.unitDate, modificationDate: probe.modificationDate)
        let answers = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for index in 0..<1_000 { group.addTask { freshness.isCurrent(files[index % files.count]) } }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(answers.allSatisfy { $0 })
        // Two tasks may race on a file's first answer; never more lookups than questions, and at least one per file.
        #expect((50...1_000).contains(probe.units.withLock { $0 }))
    }
}
