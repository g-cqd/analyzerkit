internal import Synchronization

#if canImport(FoundationEssentials)
    public import FoundationEssentials
#else
    public import Foundation
#endif

/// Whether a file's index facts are current, decided once per file for a session's life (roadmap 0053, ADR-0005).
///
/// The files classified when the store was opened are answered from that ``IndexCoverage`` with no lookup; any other
/// file (one outside the corpus, from another package of the build) costs one unit lookup and one modification time,
/// then is remembered. A session is a snapshot: a file edited after its first answer keeps that answer until a new
/// session is opened.
public final class IndexFreshness: Sendable {
    private let unitDate: @Sendable (String) -> Date?
    private let modificationDate: @Sendable (String) -> Date?
    private let known: Mutex<[String: Bool]>

    /// - Parameters:
    ///   - coverage: the classification made when the store was opened.
    ///   - unitDate: the date of a file's latest unit, nil when it has none.
    ///   - modificationDate: a file's modification time, nil when it cannot be read.
    public init(
        coverage: IndexCoverage, unitDate: @escaping @Sendable (String) -> Date?,
        modificationDate: @escaping @Sendable (String) -> Date?
    ) {
        self.unitDate = unitDate
        self.modificationDate = modificationDate
        var known: [String: Bool] = [:]
        known.reserveCapacity(coverage.files.count)
        for file in coverage.files { known[file.path] = file.coverage == .indexed }
        self.known = Mutex(known)
    }

    /// Whether `file` (canonical) has a unit at least as new as its last change.
    ///
    /// The lookups run outside the lock, so two first questions about one file may both look it up; they get the same
    /// answer, and the first one stored is kept.
    /// - Complexity: O(1) for a file answered before; else one unit lookup and one `stat`.
    public func isCurrent(_ file: String) -> Bool {
        if let answer = known.withLock({ $0[file] }) { return answer }
        let coverage = IndexCoverage.classify([file], unitDate: unitDate, modificationDate: modificationDate)
        let current = coverage.files.first?.coverage == .indexed
        return known.withLock { known in
            if let first = known[file] { return first }
            known[file] = current
            return current
        }
    }
}
