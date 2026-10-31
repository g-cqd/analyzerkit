#if canImport(IndexStoreDB)
    public import IndexStoreDB
    import SourceCorpus

    #if canImport(FoundationEssentials)
        internal import FoundationEssentials
    #else
        internal import Foundation
    #endif

    /// The queries swift-search, arcleak and deadwood make of an index store, written once (roadmap 0054, ADR-0027).
    ///
    /// Every path comes back canonical (`SourcePath.canonical`): the store records the paths the compiler was given,
    /// `/private/var/…` for a temporary directory the corpus spells `/var/…`, so callers compare with corpus paths as
    /// they are. Each recorded spelling is canonicalized once per instance.
    public final class IndexQueries: @unchecked Sendable {
        /// One occurrence, its path canonical. It keeps IndexStoreDB's own record and reads its fields from it, so a
        /// query costs the store's work plus one canonical path (roadmap 0054's bar).
        public struct Occurrence: @unchecked Sendable, Hashable {
            public let record: SymbolOccurrence
            /// The file, canonical.
            public let file: String

            public var usr: String { record.symbol.usr }
            /// As the index spells it: `fetch(id:)`, `Store`.
            public var name: String { record.symbol.name }
            public var kind: IndexSymbolKind { record.symbol.kind }
            public var line: Int { record.location.line }
            /// UTF-8 column, 1-based.
            public var column: Int { record.location.utf8Column }
            public var roles: SymbolRole { record.roles }
            public var module: String { record.location.moduleName }
            public var isSystem: Bool { record.location.isSystem }
            /// The symbol this one is a child of (`childOf`), if the occurrence records one.
            public var container: Symbol? { record.relations.first { $0.roles.contains(.childOf) }?.symbol }

            /// The name before its argument labels: `fetch` for `fetch(id:)`.
            public var baseName: String { IndexQueries.baseName(name) }

            public var isDefinitionLike: Bool { roles.contains(.definition) || roles.contains(.declaration) }

            /// One symbol at one place with the same roles.
            public static func == (lhs: Occurrence, rhs: Occurrence) -> Bool {
                (lhs.usr, lhs.file, lhs.line, lhs.column, lhs.roles.rawValue)
                    == (rhs.usr, rhs.file, rhs.line, rhs.column, rhs.roles.rawValue)
            }

            public func hash(into hasher: inout Hasher) {
                hasher.combine(usr)
                hasher.combine(file)
                hasher.combine(line)
                hasher.combine(column)
                hasher.combine(roles.rawValue)
            }
        }

        public let database: IndexStoreDB
        private let lock = NSLock()
        private var spellings: [String: String] = [:]

        public init(database: IndexStoreDB) {
            self.database = database
        }

        public convenience init(session: IndexStoreSession) {
            self.init(database: session.database)
        }

        // MARK: Files

        /// Every occurrence the store records in `file` (any spelling of it), in the store's order.
        public func occurrences(inFile file: String) -> [Occurrence] {
            var local = Spellings()
            return database.symbolOccurrences(inFilePath: file).map { convert($0, &local) }
        }

        /// The definitions and declarations the store records in `file`, sorted by line, column and USR.
        public func definitions(inFile file: String) -> [Occurrence] {
            occurrences(inFile: file).filter(\.isDefinitionLike).sorted {
                ($0.line, $0.column, $0.usr) < ($1.line, $1.column, $1.usr)
            }
        }

        // MARK: Symbols

        /// The occurrences of `usr` with any of `roles`, in the store's order.
        public func occurrences(ofUSR usr: String, roles: SymbolRole = .all) -> [Occurrence] {
            // The collecting call, not `forEachSymbolOccurrence`: indexstore-db reads the records concurrently there
            // (ADR-0025's heavy row).
            var local = Spellings()
            return database.occurrences(ofUSR: usr, roles: roles).map { convert($0, &local) }
        }

        /// Whether `usr` has an occurrence with any of `roles`; stops at the first.
        public func hasOccurrences(ofUSR usr: String, roles: SymbolRole) -> Bool {
            var found = false
            database.forEachSymbolOccurrence(byUSR: usr, roles: roles) { _ in
                found = true
                return false
            }
            return found
        }

        /// The canonical occurrences of the symbols named exactly `name` (`fetch(id:)`, `Store`).
        public func occurrences(named name: String) -> [Occurrence] {
            canonical(containing: name, anchorEnd: true) { _ in true }
        }

        /// The canonical occurrences of the symbols whose base name is `name`: `fetch` finds `fetch(id:)` and `fetch()`,
        /// not `fetchAll()`. A prefix query, filtered on the name before `(`.
        public func occurrences(baseNamed name: String) -> [Occurrence] {
            canonical(containing: name, anchorEnd: false) { Self.baseName($0) == name }
        }

        /// The names of the types that contain `occurrence`, outermost first, from `childOf` relations; at most 32
        /// levels, and never a module.
        public func containers(of occurrence: Occurrence) -> [String] {
            var names: [String] = []
            var parent = occurrence.container
            for _ in 0..<32 {
                guard let symbol = parent, symbol.kind != .module else { break }
                names.append(Self.baseName(symbol.name))
                guard let definition = occurrences(ofUSR: symbol.usr, roles: [.definition]).first else { break }
                parent = definition.container
            }
            return names.reversed()
        }

        /// `fetch` for `fetch(id:)`; a name that starts with `(` is kept whole.
        public static func baseName(_ name: String) -> String {
            guard let open = name.firstIndex(of: "("), open != name.startIndex else { return name }
            return String(name[..<open])
        }

        // MARK: Conversion

        private func canonical(containing name: String, anchorEnd: Bool, keep: (String) -> Bool) -> [Occurrence] {
            var found: [Occurrence] = []
            var local = Spellings()
            database.forEachCanonicalSymbolOccurrence(
                containing: name, anchorStart: true, anchorEnd: anchorEnd, subsequence: false, ignoreCase: false
            ) { occurrence in
                if keep(occurrence.symbol.name) { found.append(self.convert(occurrence, &local)) }
                return true
            }
            return found
        }

        /// `local` holds the spelling the query met last.
        /// `local` holds the spelling the query met last.
        private func convert(_ occurrence: SymbolOccurrence, _ local: inout Spellings) -> Occurrence {
            Occurrence(record: occurrence, file: path(occurrence.location.path, &local))
        }

        /// The spelling a query met last: consecutive occurrences in one file are answered with one comparison and no
        /// hash of the path; the rest go to the shared table.
        private struct Spellings {
            var previous: (recorded: String, canonical: String)?
        }

        private func path(_ recorded: String, _ local: inout Spellings) -> String {
            if let previous = local.previous, previous.recorded == recorded { return previous.canonical }
            let path = canonicalPath(recorded)
            local.previous = (recorded, path)
            return path
        }

        private func canonicalPath(_ recorded: String) -> String {
            lock.lock()
            defer { lock.unlock() }
            if let known = spellings[recorded] { return known }
            let path = SourcePath.canonical(recorded)
            spellings[recorded] = path
            return path
        }
    }
#endif
