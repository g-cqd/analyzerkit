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
        IndexCoverage(
            files: files.map { file in
                guard let unit = unitDate(file) else { return (file, .notIndexed) }
                guard let modified = modificationDate(file) else { return (file, .unreadable) }
                return (file, modified > unit ? .changedSinceBuild : .indexed)
            })
    }

    /// The files of one class, in order.
    public func paths(_ coverage: Class) -> [String] { files.filter { $0.coverage == coverage }.map(\.path) }

    /// Whether the store is used at all: some analyzed file is indexed. When none is, the store does not describe these
    /// files (a wrong path, another build, or a store with relative unit paths), and no symbol is asked of it.
    public var isUsable: Bool { files.contains { $0.coverage == .indexed } }

    /// The files not covered, as a report lists them.
    public var skippedFiles: [SkippedFile] {
        files.compactMap { file in
            switch file.coverage {
            case .indexed: nil
            case .notIndexed: SkippedFile(path: file.path, reason: .notIndexed)
            case .changedSinceBuild: SkippedFile(path: file.path, reason: .changedSinceBuild)
            case .unreadable: SkippedFile(path: file.path, reason: .unreadable)
            }
        }
    }

    /// The notes a report carries about the store: one when it is not used, one per class of file it does not cover.
    public func runNotes(store: String, verbose: Bool) -> [RunNote] {
        guard isUsable else {
            return [
                RunNote(
                    code: "index-not-used", severity: "warning",
                    message: "the index store at \(store) describes none of the \(files.count) analyzed files (a wrong "
                        + "path, another build or scheme, or a store with relative unit paths); the analysis ran without it"
                )
            ]
        }
        var notes: [RunNote] = []
        let changed = paths(.changedSinceBuild)
        if !changed.isEmpty {
            notes.append(
                RunNote(
                    code: "index-changed-since-build", severity: "note",
                    message: "\(changed.count) analyzed file(s) changed after the index store was built; their index "
                        + "facts are not used; rebuild to cover them", paths: changed, verbose: verbose))
        }
        let missing = paths(.notIndexed)
        if !missing.isEmpty {
            notes.append(
                RunNote(
                    code: "index-not-indexed", severity: "note",
                    message: "\(missing.count) analyzed file(s) have no unit in the index store (not built by this "
                        + "scheme, or not built yet); their index facts are missing", paths: missing, verbose: verbose))
        }
        let unreadable = paths(.unreadable)
        if !unreadable.isEmpty {
            notes.append(
                RunNote(
                    code: "index-unreadable", severity: "warning",
                    message: "the modification time of \(unreadable.count) analyzed file(s) could not be read; their "
                        + "index facts are not used", paths: unreadable, verbose: verbose))
        }
        return notes
    }
}
