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

    /// Probes A6, D1 and A1 of research 2026-10-29-index-store-reports-reviewed, on stores the compiler writes.
    @Suite(.enabled("needs a trusted libIndexStore and swiftc") { await library() != nil && compiler != nil })
    struct IndexStoreSessionTests {
        private struct Tree {
            let root: String
            let cache: String

            func file(_ path: String, _ contents: String) throws -> String {
                let full = root + "/" + path
                try FileManager.default.createDirectory(
                    atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                try contents.write(toFile: full, atomically: true, encoding: .utf8)
                return full
            }

            /// Compiles `sources` (paths under the root) as module `module`, indexing into `store`.
            func index(_ sources: [String], into store: String, module: String = "Fixture", relative: Bool = false)
                throws
            {
                guard let compiler else { return }
                var arguments = [
                    "-sdk", compiler.sdk, "-index-store-path", root + "/" + store, "-index-ignore-system-modules",
                    "-module-name", module, "-parse-as-library", "-emit-module", "-emit-module-path",
                    root + "/modules/" + module + ".swiftmodule",
                ]
                if relative {
                    // swiftc sees the temporary directory as /private/var/…, so both spellings are mapped, and the
                    // sources are given relative to the working directory.
                    arguments += ["-file-prefix-map", root + "=.", "-file-prefix-map", "/private" + root + "=."]
                    arguments += sources
                } else {
                    arguments += sources.map { root + "/" + $0 }
                }
                try #require(run(compiler.swiftc, arguments, in: root) != nil, "swiftc failed")
            }

            /// Every path under the root, to show nothing was created there.
            func listing() -> [String] { (FileManager.default.subpaths(atPath: root) ?? []).sorted() }
        }

        private func tree(_ body: (Tree) async throws -> Void) async throws {
            let base = FileManager.default.temporaryDirectory.appending(path: "index-session-\(UUID().uuidString)")
                .resolvingSymlinksInPath().path
            let tree = Tree(root: base + "/tree", cache: base + "/cache")
            try FileManager.default.createDirectory(atPath: tree.root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(atPath: base) }
            try "gitdir: none".write(toFile: tree.root + "/.git", atomically: true, encoding: .utf8)
            try await body(tree)
        }

        private func open(_ tree: Tree, _ path: String, _ files: [String]) async throws -> IndexStoreSession.Outcome {
            let dylib = try #require(await library())
            return IndexStoreSession.open(
                tree.root + "/" + path, cacheRoot: tree.cache, library: dylib, analyzedFiles: files)
        }

        @Test
        func `a store opened at any depth has one database under the cache root, and nothing is written elsewhere`()
            async throws
        {
            try await tree { t in
                let hub = try t.file("src/Hub.swift", "class Hub {\n    var plugin: Plugin?\n    init() {}\n}\n")
                let plugin = try t.file("src/Plugin.swift", "class Plugin {\n    var hub: Hub?\n    init() {}\n}\n")
                try t.index(["src/Hub.swift", "src/Plugin.swift"], into: "dd/Index.noindex/DataStore")
                let before = t.listing()
                var databases: Set<String> = []
                for given in ["dd", "dd/Index.noindex", "dd/Index.noindex/DataStore"] {
                    guard case .usable(let session) = try await open(t, given, [hub, plugin]) else {
                        Issue.record("\(given) did not open")
                        continue
                    }
                    #expect(session.store == t.root + "/dd/Index.noindex/DataStore")
                    #expect(session.databaseDirectory.hasPrefix(t.cache + "/index/"))
                    #expect(FileManager.default.fileExists(atPath: session.databaseDirectory))
                    #expect(!session.database.symbolOccurrences(inFilePath: hub).isEmpty, "a query answers")
                    databases.insert(session.databaseDirectory)
                }
                #expect(databases.count == 1)
                #expect(t.listing() == before)
            }
        }

        /// A store the user cannot write to (a shared DerivedData, a CI artifact) opens, since nothing is written to it.
        /// Written after the implementation, as a guard: it passed on its first run.
        @Test func `a read-only store opens`() async throws {
            try await tree { t in
                let hub = try t.file("src/Hub.swift", "class Hub {\n    init() {}\n}\n")
                try t.index(["src/Hub.swift"], into: "store")
                let store = t.root + "/store"
                let paths = [store] + (FileManager.default.subpaths(atPath: store) ?? []).map { store + "/" + $0 }
                for path in paths {
                    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: path)
                }
                defer {
                    for path in paths {
                        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
                    }
                }
                guard case .usable(let session) = try await open(t, "store", [hub]) else {
                    Issue.record("a read-only store did not open")
                    return
                }
                #expect(session.coverage.isUsable)
            }
        }

        @Test func `a path that is not a store is refused, and neither it nor the cache root gets anything`()
            async throws
        {
            try await tree { t in
                let hub = try t.file("src/Hub.swift", "class Hub {}\n")
                let before = t.listing()
                guard case .notAStore(let reason) = try await open(t, "src", [hub]) else {
                    Issue.record("src opened as a store")
                    return
                }
                #expect(reason.contains("not an index store"))
                #expect(t.listing() == before)
                #expect(!FileManager.default.fileExists(atPath: t.cache))
            }
        }

        /// A store whose units hold relative paths matches no absolute analyzed path, so it is not usable, and so it is
        /// never queried (a symbol query on it can abort libIndexStore).
        @Test func `a store with relative unit paths is not usable`() async throws {
            try await tree { t in
                let hub = try t.file("src/Hub.swift", "class Hub {\n    init() {}\n}\n")
                try t.index(["src/Hub.swift"], into: "store", relative: true)
                guard case .notUsable(_, let coverage) = try await open(t, "store", [hub]) else {
                    Issue.record("a relative-path store was usable")
                    return
                }
                #expect(coverage.files.map(\.coverage) == [.notIndexed])
                #expect(coverage.runNotes(store: "store", verbose: false).map(\.code) == ["index-not-used"])
            }
        }

        @Test func `a never-compiled file and an edited one are classified apart`() async throws {
            try await tree { t in
                let hub = try t.file("src/Hub.swift", "class Hub {\n    var plugin: Plugin?\n    init() {}\n}\n")
                let plugin = try t.file("src/Plugin.swift", "class Plugin {\n    var hub: Hub?\n    init() {}\n}\n")
                try t.index(["src/Hub.swift", "src/Plugin.swift"], into: "store")
                let script = try t.file("src/Script.swift", "let x = 1\n")
                try FileManager.default.setAttributes(
                    [.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: plugin)
                guard case .usable(let session) = try await open(t, "store", [hub, plugin, script]) else {
                    Issue.record("the store did not open")
                    return
                }
                #expect(session.coverage.files.map(\.coverage) == [.indexed, .changedSinceBuild, .notIndexed])
            }
        }

        /// The session's freshness agrees with its coverage on the analyzed files and looks up the others (0053).
        @Test func `freshness answers analyzed files from the coverage and looks up the rest`() async throws {
            try await tree { t in
                let hub = try t.file("src/Hub.swift", "class Hub {\n    var plugin: Plugin?\n    init() {}\n}\n")
                let plugin = try t.file("src/Plugin.swift", "class Plugin {\n    var hub: Hub?\n    init() {}\n}\n")
                try t.index(["src/Hub.swift", "src/Plugin.swift"], into: "store")
                let outside = try t.file("src/Outside.swift", "let y = 2\n")
                guard case .usable(let session) = try await open(t, "store", [hub]) else {
                    Issue.record("the store did not open")
                    return
                }
                #expect(session.freshness.isCurrent(hub))
                #expect(session.freshness.isCurrent(SourcePath.canonical(plugin)))
                #expect(!session.freshness.isCurrent(outside))
            }
        }
    }
#endif
