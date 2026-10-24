import Foundation

/// A throwaway directory, removed when the value goes out of scope of `use`.
struct Scratch {
    let root: URL

    @discardableResult
    static func with<T>(_ body: (Scratch) throws -> T) throws -> T {
        let root = FileManager.default.temporaryDirectory.appending(path: "source-corpus-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        return try body(Scratch(root: root))
    }

    @discardableResult
    static func withAsync<T>(_ body: (Scratch) async throws -> T) async throws -> T {
        let root = FileManager.default.temporaryDirectory.appending(path: "source-corpus-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        return try await body(Scratch(root: root))
    }

    @discardableResult
    func write(_ path: String, _ contents: String = "let value = 1\n") throws -> String {
        let file = root.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return file.path
    }

    func link(_ path: String, to destination: String) throws {
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: path).path, withDestinationPath: destination)
    }

    func path(_ component: String) -> String { root.appending(path: component).path }
}
