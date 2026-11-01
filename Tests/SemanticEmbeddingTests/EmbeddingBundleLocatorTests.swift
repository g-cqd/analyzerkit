import Foundation
import SemanticEmbedding
import Testing

@Suite struct EmbeddingBundleLocatorTests {
    private func scratch() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "bundle-locator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.resolvingSymlinksInPath()
    }

    private func path(_ url: URL?) -> String? { url?.resolvingSymlinksInPath().path }

    private func model(in directory: URL, named name: String = "m.mlmodelc") throws {
        try FileManager.default.createDirectory(at: directory.appending(path: name), withIntermediateDirectories: true)
    }

    @Test func `the executable's Models MiniLM is found when it holds a model`() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appending(path: "bin")
        try model(in: bin.appending(path: "Models/MiniLM"))
        let found = EmbeddingBundleLocator.directory(tool: "arcleak", executableDirectory: bin, override: nil)
        #expect(path(found) == path(bin.appending(path: "Models/MiniLM")))
    }

    @Test func `the share layout next to bin is found, under the tool's own name`() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appending(path: "bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try model(in: root.appending(path: "share/deadwood/Models/MiniLM"), named: "x.mlpackage")
        #expect(
            path(EmbeddingBundleLocator.directory(tool: "deadwood", executableDirectory: bin, override: nil))
                == path(root.appending(path: "share/deadwood/Models/MiniLM"))
        )
        #expect(
            path(EmbeddingBundleLocator.directory(tool: "dolly", executableDirectory: bin, override: nil)) == path(nil)
        )
    }

    @Test func `the override wins, an empty one is ignored, and a directory without a model does not count`() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appending(path: "bin")
        try model(in: bin.appending(path: "Models/MiniLM"))
        let other = root.appending(path: "other")
        try model(in: other)
        #expect(
            path(EmbeddingBundleLocator.directory(tool: "t", executableDirectory: bin, override: other.path))
                == path(other)
        )
        #expect(
            path(EmbeddingBundleLocator.directory(tool: "t", executableDirectory: bin, override: ""))
                == path(bin.appending(path: "Models/MiniLM"))
        )
        let empty = root.appending(path: "empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        #expect(
            path(EmbeddingBundleLocator.directory(tool: "t", executableDirectory: bin, override: empty.path))
                == path(bin.appending(path: "Models/MiniLM")),
            "an override with no model falls through to the next candidate"
        )
    }

    @Test func `nothing found is nil, and the variable is named after the tool`() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(
            path(EmbeddingBundleLocator.directory(tool: "t", executableDirectory: root, override: nil)) == path(nil)
        )
        #expect(EmbeddingBundleLocator.environmentVariable(tool: "arcleak") == "ARCLEAK_EMBEDDING_BUNDLE")
        #expect(EmbeddingBundleLocator.environmentVariable(tool: "swift-search") == "SWIFT_SEARCH_EMBEDDING_BUNDLE")
    }
}
