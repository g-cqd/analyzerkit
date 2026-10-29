import Foundation
import IndexStoreSupport
import ProjectModel
import Testing

/// Probes A6 and D1 (research 2026-10-29-index-store-reports-reviewed): a store given at the wrong depth must resolve to
/// the store, and a path that holds none must be refused without anything being created in it.
@Suite struct IndexStoreLocationTests {
    private struct Tree {
        let root: String

        func directory(_ path: String) throws {
            try FileManager.default.createDirectory(atPath: root + "/" + path, withIntermediateDirectories: true)
        }

        func file(_ path: String, _ contents: String = "") throws {
            try directory((path as NSString).deletingLastPathComponent)
            try contents.write(toFile: root + "/" + path, atomically: true, encoding: .utf8)
        }

        /// A store as libIndexStore writes it: `vN/records` and `vN/units`, with one record so it is not empty.
        func store(_ path: String) throws {
            try file(path + "/v5/records/AB/Hub.swift-1ABC")
            try directory(path + "/v5/units")
        }

        func link(_ path: String, to destination: String) throws {
            try FileManager.default.createSymbolicLink(atPath: root + "/" + path, withDestinationPath: destination)
        }

        /// Every path under the root, to show nothing was created.
        func listing() -> [String] {
            (FileManager.default.subpaths(atPath: root) ?? []).sorted()
        }
    }

    private func tree(_ body: (Tree) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "index-location-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        // A repository boundary, so no lookup walks the temporary directory's ancestors.
        try "gitdir: none".write(toFile: url.path + "/.git", atomically: true, encoding: .utf8)
        try body(Tree(root: url.path))
    }

    @Test func `an Xcode store given at any depth resolves to the DataStore`() throws {
        try tree { t in
            try t.store("dd/Index.noindex/DataStore")
            let store = t.root + "/dd/Index.noindex/DataStore"
            for given in ["dd", "dd/Index.noindex", "dd/Index.noindex/DataStore", "dd/Index.noindex/DataStore/v5"] {
                #expect(IndexStoreLocation.resolve(t.root + "/" + given) == .store(store), "\(given)")
            }
        }
    }

    @Test func `a SwiftPM store resolves from the build directory, a configuration, or through its link`() throws {
        try tree { t in
            try t.store("pkg/.build/arm64-apple-macosx/debug/index/store")
            try t.link("pkg/.build/debug", to: "arm64-apple-macosx/debug")
            let store = t.root + "/pkg/.build/arm64-apple-macosx/debug/index/store"
            for given in [
                "pkg/.build", "pkg/.build/debug", "pkg/.build/arm64-apple-macosx/debug", "pkg/.build/debug/index/store",
            ] {
                #expect(IndexStoreLocation.resolve(t.root + "/" + given) == .store(store), "\(given)")
            }
        }
    }

    @Test func `a store without a version directory is still a store`() throws {
        try tree { t in
            try t.file("flat/records/AB/Hub.swift-1ABC")
            try t.directory("flat/units")
            #expect(IndexStoreLocation.resolve(t.root + "/flat") == .store(t.root + "/flat"))
        }
    }

    @Test func `a path holding no store is refused, says what to pass, and nothing is created`() throws {
        try tree { t in
            try t.directory("empty")
            try t.file("project/Sources/Hub.swift", "class Hub {}\n")
            let before = t.listing()
            for given in ["empty", "project", "project/Sources/Hub.swift", "missing"] {
                guard case .notAStore(let path, let reason) = IndexStoreLocation.resolve(t.root + "/" + given) else {
                    Issue.record("\(given) resolved to a store")
                    continue
                }
                #expect(path == t.root + "/" + given)
                #expect(reason.contains("Index.noindex/DataStore"), "\(reason)")
                #expect(reason.contains("index/store"), "\(reason)")
            }
            #expect(t.listing() == before)
        }
    }

    @Test func `one store has one database directory under the cache root, whatever its spelling`() throws {
        try tree { t in
            try t.store("dd/Index.noindex/DataStore")
            try t.store("other/Index.noindex/DataStore")
            try t.link("alias", to: "dd")
            let cache = t.root + "/cache"
            let direct = IndexStoreLocation.databaseDirectory(
                forStore: t.root + "/dd/Index.noindex/DataStore", cacheRoot: cache)
            let viaLink = IndexStoreLocation.databaseDirectory(
                forStore: t.root + "/alias/Index.noindex/DataStore", cacheRoot: cache)
            let other = IndexStoreLocation.databaseDirectory(
                forStore: t.root + "/other/Index.noindex/DataStore", cacheRoot: cache)
            #expect(direct.hasPrefix(cache + "/index/"))
            #expect(direct == viaLink)
            #expect(direct != other)
            #expect(!FileManager.default.fileExists(atPath: cache), "computing the path creates nothing")
        }
    }

    @Test func `a project's store is found in its build directory, else in DerivedData for its workspace`() throws {
        try tree { t in
            try t.file("app/App.xcodeproj/project.pbxproj")
            try t.file("app/Sources/App.swift")
            let layout = try #require(ProjectLayout.discover(paths: [t.root + "/app/Sources/App.swift"]))
            let derivedData = t.root + "/DerivedData"
            #expect(IndexStoreLocation.discover(layout: layout, derivedDataRoots: [derivedData]) == nil)

            try t.store("DerivedData/App-abc/Index.noindex/DataStore")
            let plist = try PropertyListSerialization.data(
                fromPropertyList: ["WorkspacePath": t.root + "/app/App.xcodeproj"], format: .binary, options: 0)
            try plist.write(to: URL(fileURLWithPath: derivedData + "/App-abc/info.plist"))
            #expect(
                IndexStoreLocation.discover(layout: layout, derivedDataRoots: [derivedData])
                    == t.root + "/DerivedData/App-abc/Index.noindex/DataStore")

            try t.store("app/.build/arm64-apple-macosx/debug/index/store")
            #expect(
                IndexStoreLocation.discover(layout: layout, derivedDataRoots: [derivedData])
                    == t.root + "/app/.build/arm64-apple-macosx/debug/index/store")
        }
    }
}
