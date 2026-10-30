#if canImport(IndexStoreDB)
    public import IndexStoreDB

    #if canImport(FoundationEssentials)
        internal import FoundationEssentials
    #else
        internal import Foundation
    #endif

    /// An open index store whose coverage of the analyzed files was checked (ADR-0004, ADR-0005; roadmap 0010).
    ///
    /// The only way to a database is ``open(_:cacheRoot:library:analyzedFiles:)``, which returns one only when some
    /// analyzed file is indexed: a store that describes none of them (a wrong build, or one with relative unit paths, on
    /// which a symbol query can abort libIndexStore) is never queried.
    public final class IndexStoreSession: @unchecked Sendable {
        /// The store's root, canonical.
        public let store: String
        /// The database directory, under the cache root.
        public let databaseDirectory: String
        /// The database. IndexStoreDB serialises its own access, so one session may be queried from any thread.
        public let database: IndexStoreDB
        /// How the store covered the analyzed files when it was opened.
        public let coverage: IndexCoverage
        /// Whether a file's index facts are current, for any file: the analyzed ones from ``coverage``, others looked
        /// up once each and remembered for the session's life.
        public let freshness: IndexFreshness

        init(store: String, databaseDirectory: String, database: IndexStoreDB, coverage: IndexCoverage) {
            self.store = store
            self.databaseDirectory = databaseDirectory
            self.database = database
            self.coverage = coverage
            let reader = UncheckedDatabase(database)
            freshness = IndexFreshness(
                coverage: coverage, unitDate: { reader.database.dateOfLatestUnitFor(filePath: $0) },
                modificationDate: Self.modificationDate)
        }

        /// A file's modification time, nil when it cannot be read.
        @Sendable static func modificationDate(_ file: String) -> Date? {
            (try? FileManager.default.attributesOfItem(atPath: file))?[.modificationDate] as? Date
        }

        /// What opening a store gave.
        public enum Outcome {
            /// The store covers some analyzed file; the session may be queried.
            case usable(IndexStoreSession)
            /// The store opened but indexes none of the analyzed files; its notes say so.
            case notUsable(store: String, coverage: IndexCoverage)
            /// `path` is not a store; nothing was created anywhere.
            case notAStore(reason: String)
            /// The library or the database could not be opened.
            case failed(reason: String)
        }

        /// Resolves `path` (``IndexStoreLocation/resolve(_:)``), opens it with its database under `cacheRoot` using the
        /// trusted `libIndexStore` at `library`, and classifies `analyzedFiles` against it.
        public static func open(
            _ path: String, cacheRoot: String, library: String, analyzedFiles: [String]
        ) -> Outcome {
            let store: String
            switch IndexStoreLocation.resolve(path) {
            case .store(let resolved): store = resolved
            case .notAStore(_, let reason): return .notAStore(reason: reason)
            }
            let trust = BinaryTrustChecker.assess(library)
            guard trust.isTrusted else {
                return .failed(reason: "libIndexStore at \(library) is not trusted: \(trust.rejection ?? "")")
            }
            let databaseDirectory = IndexStoreLocation.databaseDirectory(forStore: store, cacheRoot: cacheRoot)
            let database: IndexStoreDB
            do {
                try FileManager.default.createDirectory(atPath: databaseDirectory, withIntermediateDirectories: true)
                database = try IndexStoreDB(
                    storePath: store, databasePath: databaseDirectory,
                    library: IndexStoreLibrary(dylibPath: trust.path), waitUntilDoneInitializing: true)
            } catch {
                return .failed(reason: "the index store at \(store) could not be opened: \(error)")
            }
            let coverage = IndexCoverage.classify(
                analyzedFiles, unitDate: { database.dateOfLatestUnitFor(filePath: $0) },
                modificationDate: modificationDate)
            guard coverage.isUsable else { return .notUsable(store: store, coverage: coverage) }
            return .usable(
                IndexStoreSession(
                    store: store, databaseDirectory: databaseDirectory, database: database, coverage: coverage))
        }
    }

    /// IndexStoreDB serialises its own access (see ``IndexStoreSession/database``) but is not declared `Sendable`.
    private struct UncheckedDatabase: @unchecked Sendable {
        let database: IndexStoreDB
        init(_ database: IndexStoreDB) { self.database = database }
    }
#endif
