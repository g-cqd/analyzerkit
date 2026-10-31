internal import AemiKernel
public import ProjectModel
internal import SourceCorpus

#if canImport(FoundationEssentials)
    internal import FoundationEssentials
#else
    internal import Foundation
#endif

/// Where an index store is, read from the file system without writing to it (ADR-0004, roadmap 0010).
///
/// libIndexStore creates `vN/` in whatever directory it is given and the database an `IndexDatabase/` beside it, so a
/// path that is not a store must be refused before anything opens it (probes A6, D1).
public enum IndexStoreLocation {
    /// What a path given as an index store turned out to be.
    public enum Resolution: Sendable, Equatable {
        /// The store's root, canonical: the directory IndexStoreDB is given, holding `vN/records` and `vN/units` (or
        /// `records` and `units` directly).
        case store(String)
        /// Nothing at or below the path is a store; `reason` says what to pass instead.
        case notAStore(path: String, reason: String)
    }

    /// The store `path` names: the store itself, one of its `vN` directories, Xcode's `Index.noindex` or a DerivedData
    /// build root above it, or a SwiftPM `.build` directory or build configuration holding `index/store`. Reads only.
    public static func resolve(_ path: String) -> Resolution {
        let directory = SourcePath.canonical(path)
        let name = directory.split(separator: "/").last.map(String.init) ?? directory
        // IndexStoreDB is given the root and reads `vN` itself; given `vN`, it finds an empty store.
        var candidates = isVersionName(name) ? [Self.parent(of: directory)] : []
        candidates.append(directory)
        candidates += [
            directory + "/DataStore",  // Index.noindex
            directory + "/Index.noindex/DataStore",  // a DerivedData build root
            directory + "/index/store",  // a SwiftPM build configuration
        ]
        candidates += swiftPMStores(inBuildDirectory: directory)
        for candidate in candidates where isStore(candidate) {
            return .store(SourcePath.canonical(candidate))
        }
        let what = isDirectory(directory) ? "is not an index store" : "is not a directory"
        return .notAStore(
            path: path,
            reason: "\(path) \(what): no records or units in it, in a vN directory below it, or where a build puts a "
                + "store below it; pass the store directory, <DerivedData>/<Project>-<hash>/Index.noindex/DataStore "
                + "for Xcode or .build/debug/index/store for SwiftPM")
    }

    /// The store for a project: SwiftPM's under the layout root's `.build` first, then the newest DerivedData store
    /// whose workspace is one of the layout's containers. Nil when there is none.
    public static func discover(layout: ProjectLayout, derivedDataRoots: [String]) -> String? {
        if case .store(let store) = resolve(layout.root + "/.build") { return store }
        for candidate in layout.derivedDataStores(under: derivedDataRoots) {
            if case .store(let store) = resolve(candidate) { return store }
        }
        return nil
    }

    /// Where the database for `store` lives: `<cacheRoot>/index/<hash of the store's canonical path>`, so every tool that
    /// shares a cache root shares the database, and nothing is written next to the store.
    public static func databaseDirectory(forStore store: String, cacheRoot: String) -> String {
        let hash = XXH64.hash(Array(SourcePath.canonical(store).utf8))
        let hex = String(hash, radix: 16)
        return cacheRoot + "/index/" + String(repeating: "0", count: 16 - hex.count) + hex
    }

    /// The stores a SwiftPM `.build` directory may hold: the background index's, each configuration's (by its link
    /// and under each target triple), and the Swift Build system's `out`.
    private static func swiftPMStores(inBuildDirectory directory: String) -> [String] {
        var stores = [
            directory + "/index-build/index/store", directory + "/debug/index/store",
            directory + "/release/index/store", directory + "/out",
        ]
        let triples = ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []).sorted()
        for triple in triples where triple.contains("-") {
            stores += [
                directory + "/" + triple + "/debug/index/store", directory + "/" + triple + "/release/index/store",
            ]
        }
        return stores
    }

    /// Whether `directory` holds `records` or `units`, directly or in a `vN` directory.
    private static func isStore(_ directory: String) -> Bool {
        guard isDirectory(directory) else { return false }
        if holdsRecords(directory) { return true }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        return names.contains { isVersionName($0) && holdsRecords(directory + "/" + $0) }
    }

    private static func holdsRecords(_ directory: String) -> Bool {
        isDirectory(directory + "/records") || isDirectory(directory + "/units")
    }

    private static func isVersionName(_ name: String) -> Bool {
        name.count > 1 && name.hasPrefix("v") && name.dropFirst().allSatisfy(\.isASCIIDigit)
    }

    /// Whether `path` is a directory, following a link; FoundationEssentials has no `ObjCBool`.
    private static func isDirectory(_ path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: SourcePath.canonical(path)))?[.type] as? FileAttributeType
            == .typeDirectory
    }

    /// `path` without its last component (`/a/b` → `/a`, `/b` → `/`), which FoundationEssentials does not have.
    private static func parent(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return slash == path.startIndex ? "/" : String(path[..<slash])
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
