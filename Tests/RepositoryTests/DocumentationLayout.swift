import Foundation

/// The documentation law of `development/WHITE-PAPER.md`, as functions over file names and text, so tests can break each
/// rule on purpose (roadmap 0001).
enum DocumentationLayout {
    static let maximumWhitePaperLines = 200
    static let maximumDiaryLines = 256

    /// The repository root, found from this file's path (`Tests/RepositoryTests/<file>`).
    static let repositoryRoot: URL = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    /// The Markdown files directly in `development/<directory>`: name and text, sorted by name.
    static func documents(in directory: String) -> [(name: String, text: String)] {
        let url = repositoryRoot.appending(path: "development/\(directory)")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return names.filter { $0.hasSuffix(".md") }.sorted()
            .compactMap { name in
                (try? String(contentsOf: url.appending(path: name), encoding: .utf8)).map { (name, $0) }
            }
    }

    static func lineCount(_ text: String) -> Int {
        text.split(separator: "\n", omittingEmptySubsequences: false).count - 1
    }

    static func whitePaperProblems(_ text: String) -> [String] { [] }

    static func adrProblems(in records: [(name: String, text: String)]) -> [String] { [] }

    static func roadmapProblems(in entries: [(name: String, text: String)]) -> [String] { [] }

    static func diaryProblems(in files: [(name: String, text: String)]) -> [String] { [] }

    static func referenceProblems(
        in documents: [(name: String, text: String)], adrs: Set<String>, roadmap: Set<String>, research: Set<String>
    ) -> [String] { [] }
}
