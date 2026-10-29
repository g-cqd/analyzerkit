public import ReportSupport

#if canImport(FoundationEssentials)
    public import FoundationEssentials
#else
    public import Foundation
#endif

/// How well a store describes the analyzed files, file by file (ADR-0005 items 1 and 2).
public struct IndexCoverage: Sendable, Equatable {
    public enum Class: String, Sendable, Equatable {
        /// The store has a unit for the file, built after the file last changed.
        case indexed
        /// No unit for the file: not built by this scheme, or not built at all.
        case notIndexed
        /// The file changed after its unit was written.
        case changedSinceBuild
        /// The file's modification time could not be read.
        case unreadable
    }

    /// Every analyzed file with its class, in the order given.
    public let files: [(path: String, coverage: Class)]

    public static func == (lhs: IndexCoverage, rhs: IndexCoverage) -> Bool {
        lhs.files.map(\.path) == rhs.files.map(\.path) && lhs.files.map(\.coverage) == rhs.files.map(\.coverage)
    }

    /// Classifies `files` by the date of each one's latest unit (nil: none) against its modification time (nil:
    /// unreadable).
    public static func classify(
        _ files: [String], unitDate: (String) -> Date?, modificationDate: (String) -> Date?
    ) -> IndexCoverage {
        IndexCoverage(files: [])
    }

    /// The files of one class, in order.
    public func paths(_ coverage: Class) -> [String] { [] }

    /// Whether the store is used at all: some analyzed file is indexed. When none is, the store does not describe these
    /// files (a wrong path, another build, or a store with relative unit paths), and no symbol is asked of it.
    public var isUsable: Bool { true }

    /// The files not covered, as a report lists them.
    public var skippedFiles: [SkippedFile] { [] }

    /// The notes a report carries about the store: one when it is not used, one per class of file it does not cover.
    public func runNotes(store: String, verbose: Bool) -> [RunNote] { [] }
}
