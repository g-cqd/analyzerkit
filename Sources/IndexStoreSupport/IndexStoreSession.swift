#if canImport(IndexStoreDB)
    public import IndexStoreDB

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

        init(store: String, databaseDirectory: String, database: IndexStoreDB, coverage: IndexCoverage) {
            self.store = store
            self.databaseDirectory = databaseDirectory
            self.database = database
            self.coverage = coverage
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
            .failed(reason: "not implemented")
        }
    }
#endif
