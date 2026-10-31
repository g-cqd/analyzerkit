#if canImport(IndexStoreDB)
    import Foundation
    import IndexStoreDB
    import IndexStoreSupport
    import ReportSupport
    import SourceCorpus
    import Testing

    /// A compiler to build fixture stores with, or nil when the machine has none.
    private let compiler: (swiftc: String, sdk: String)? = {
        guard let swiftc = run("/usr/bin/xcrun", ["--find", "swiftc"]),
            let sdk = run("/usr/bin/xcrun", ["--show-sdk-path"])
        else { return nil }
        return (swiftc, sdk)
    }()

    /// A trusted libIndexStore, or nil.
    private func library() async -> String? { await ToolchainResolution.resolve().libraryPath }

    /// `executable`'s first line of output, or nil when it fails.
    private func run(_ executable: String, _ arguments: [String], in directory: String? = nil) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).split(separator: "\n").first.map(String.init) ?? ""
    }

    /// The queries swift-search, arcleak and deadwood make of a store, once (roadmap 0054, ADR-0027).
    @Suite(.enabled("needs a trusted libIndexStore and swiftc") { await library() != nil && compiler != nil })
    struct IndexQueriesTests {
        private static let storeSource = """
            public struct Store {
                public init() {}
                public func fetch(id: Int) -> Int { id }
                public func fetchAll() -> [Int] { [] }
            }
            """
        private static let useSource = """
            func use() -> Int {
                let store = Store()
                _ = store.fetchAll()
                return store.fetch(id: 1)
            }
            """

        /// A fixture module of two files under the temporary directory as swiftc is given it (`/var/…`, which the
        /// store records as `/private/var/…`), opened through a session.
        private func fixture(_ body: (IndexQueries, _ store: String, _ use: String) throws -> Void) async throws {
            let compiler = try #require(compiler)
            let base = FileManager.default.temporaryDirectory.appending(path: "index-queries-\(UUID().uuidString)").path
            try FileManager.default.createDirectory(atPath: base + "/src", withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(atPath: base) }
            let store = base + "/src/Store.swift"
            let use = base + "/src/Use.swift"
            try Self.storeSource.write(toFile: store, atomically: true, encoding: .utf8)
            try Self.useSource.write(toFile: use, atomically: true, encoding: .utf8)
            let arguments = [
                "-sdk", compiler.sdk, "-index-store-path", base + "/store", "-index-ignore-system-modules",
                "-module-name", "Fixture", "-parse-as-library", "-emit-module", "-emit-module-path",
                base + "/Fixture.swiftmodule", store, use,
            ]
            try #require(run(compiler.swiftc, arguments, in: base) != nil, "swiftc failed")
            let dylib = try #require(await library())
            guard
                case .usable(let session) = IndexStoreSession.open(
                    base + "/store", cacheRoot: base + "/cache", library: dylib,
                    analyzedFiles: [store, use].map(SourcePath.canonical))
            else {
                Issue.record("the fixture store did not open")
                return
            }
            try body(IndexQueries(session: session), SourcePath.canonical(store), SourcePath.canonical(use))
        }

        @Test func `a base name finds the function whatever its labels, and nothing longer`() async throws {
            try await fixture { queries, store, _ in
                let found = queries.occurrences(baseNamed: "fetch").filter { $0.roles.contains(.definition) }
                #expect(found.map(\.name) == ["fetch(id:)"])
                #expect(found.first?.file == store && found.first?.line == 3)
            }
        }

        @Test func `a predicate over every name finds what a regex search needs`() async throws {
            try await fixture { queries, store, _ in
                let found = queries.occurrences(whereName: { $0.hasSuffix("All()") })
                #expect(Set(found.map(\.name)) == ["fetchAll()"])
                #expect(found.allSatisfy { $0.file == store || $0.file == SourcePath.canonical($0.file) })
            }
        }

        @Test func `a file's definitions, with canonical paths`() async throws {
            try await fixture { queries, store, _ in
                let names = queries.definitions(inFile: store).map(\.name)
                #expect(names.contains("Store") && names.contains("fetch(id:)") && names.contains("fetchAll()"))
                #expect(queries.definitions(inFile: store).allSatisfy { $0.file == store })
            }
        }

        @Test func `the references of a USR come with their roles, in canonical paths`() async throws {
            try await fixture { queries, _, use in
                let fetch = try #require(
                    queries.occurrences(named: "fetch(id:)").first { $0.roles.contains(.definition) })
                let calls = queries.occurrences(ofUSR: fetch.usr, roles: [.call])
                #expect(calls.map(\.file) == [use] && calls.map(\.line) == [4])
                #expect(queries.hasOccurrences(ofUSR: fetch.usr, roles: [.reference]))
                #expect(!queries.hasOccurrences(ofUSR: "s:no-such-symbol", roles: [.reference]))
            }
        }

        @Test func `a member's containers come from childOf, outermost first`() async throws {
            try await fixture { queries, _, _ in
                let fetch = try #require(
                    queries.occurrences(named: "fetch(id:)").first { $0.roles.contains(.definition) })
                #expect(queries.containers(of: fetch) == ["Store"])
                let type = try #require(queries.occurrences(named: "Store").first { $0.roles.contains(.definition) })
                #expect(queries.containers(of: type).isEmpty)
            }
        }

        @Test func `every path the store spells under /private/var comes back as the corpus spells it`() async throws {
            try await fixture { queries, store, use in
                let all = queries.occurrences(inFile: store) + queries.occurrences(inFile: use)
                #expect(!all.isEmpty)
                #expect(all.allSatisfy { $0.file == SourcePath.canonical($0.file) && !$0.file.hasPrefix("/private/") })
            }
        }
    }
#endif
