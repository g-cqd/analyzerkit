import Foundation
import ProjectModel
import Testing

@Suite struct ProjectLayoutTests {
    private func fixture(_ body: (Fixture) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "layout-\(UUID().uuidString)")
            .resolvingSymlinksInPath().path
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        try body(Fixture(root: root))
    }

    private struct Fixture {
        let root: String
        func file(_ name: String, _ content: String = "") throws {
            let url = URL(fileURLWithPath: root + "/" + name)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        func store(_ name: String, workspace: String?, accessed: TimeInterval = 0) throws -> String {
            try file(name + "/Index.noindex/DataStore/v5/records/r")
            if let workspace {
                let data = try PropertyListSerialization.data(
                    fromPropertyList: [
                        "WorkspacePath": workspace, "LastAccessedDate": Date(timeIntervalSince1970: accessed),
                    ],
                    format: .binary, options: 0)
                try data.write(to: URL(fileURLWithPath: root + "/" + name + "/info.plist"))
            }
            return root + "/" + name + "/Index.noindex/DataStore"
        }
    }

    @Test func `package and common directory do not depend on the first file`() throws {
        try fixture { f in
            try f.file("Repo/.git/HEAD")
            try f.file("Repo/Package.swift")
            try f.file("Repo/Sources/A/A.swift")
            try f.file("Repo/Tests/A/B.swift")
            let paths = ["Sources/A/A.swift", "Tests/A/B.swift"].map { f.root + "/Repo/" + $0 }
            let layout = try #require(ProjectLayout.discover(paths: paths))
            #expect(layout.root == f.root + "/Repo")
            #expect(layout.repositoryRoot == f.root + "/Repo")
            #expect(layout.packages == [f.root + "/Repo"])
            #expect(layout.containers.isEmpty)
            #expect(ProjectLayout.discover(paths: paths.reversed()) == layout)
        }
    }

    @Test func `outer Xcode project wins over nested packages and embedded workspaces`() throws {
        try fixture { f in
            try f.file("Worktree/.git", "gitdir: elsewhere")
            try f.file("Worktree/App With Spaces.xcodeproj/project.pbxproj")
            try f.file("Worktree/App With Spaces.xcodeproj/project.xcworkspace/contents.xcworkspacedata")
            try f.file("Worktree/API/Package.swift")
            try f.file("Worktree/API/Sources/Client.swift")
            try f.file("Worktree/Feature/Package.swift")
            try f.file("Worktree/.build/Dependency/Package.swift")
            let layout = try #require(ProjectLayout.discover(paths: [f.root + "/Worktree/API/Sources"]))
            #expect(layout.root == f.root + "/Worktree")
            #expect(layout.repositoryRoot == layout.root)
            #expect(layout.packages == [f.root + "/Worktree/API", f.root + "/Worktree/Feature"])
            #expect(layout.containers == [f.root + "/Worktree/App With Spaces.xcodeproj"])
            #expect(ProjectLayout.discover(paths: [layout.root]) == layout)
        }
    }

    @Test func `repository boundary wins over a project outside it and fallback uses the common directory`() throws {
        try fixture { f in
            try f.file("Outside.xcodeproj/project.pbxproj")
            try f.file("Repo/.git", "gitdir: elsewhere")
            try f.file("Repo/Sources/A.swift")
            let repo = try #require(ProjectLayout.discover(paths: [f.root + "/Repo/Sources/A.swift"]))
            #expect(repo.root == f.root + "/Repo")
            try FileManager.default.removeItem(atPath: f.root + "/Outside.xcodeproj")
            try f.file("Loose/A/One.swift")
            try f.file("Loose/B/Two.swift")
            let loose = try #require(
                ProjectLayout.discover(paths: [
                    f.root + "/Loose/A/One.swift", f.root + "/Loose/B/Two.swift",
                ]))
            #expect(loose.root == f.root + "/Loose")
            #expect(loose.repositoryRoot == nil)
            #expect(ProjectLayout.discover(paths: []) == nil)
        }
    }

    @Test func `workspace includes projects but only its own worktree DerivedData newest first`() throws {
        try fixture { f in
            for worktree in ["One", "Two"] {
                try f.file(worktree + "/.git", "gitdir: elsewhere")
                try f.file(worktree + "/App.xcworkspace/contents.xcworkspacedata")
                try f.file(worktree + "/App/App.xcodeproj/project.pbxproj")
            }
            let one = try #require(ProjectLayout.discover(paths: [f.root + "/One"]))
            #expect(one.containers == [f.root + "/One/App.xcworkspace", f.root + "/One/App/App.xcodeproj"])
            let old = try f.store("DD/name-unrelated", workspace: one.containers[0], accessed: 10)
            let new = try f.store("DD/z-new", workspace: one.containers[1], accessed: 20)
            _ = try f.store("DD/App-other-worktree", workspace: f.root + "/Two/App.xcworkspace", accessed: 100)
            _ = try f.store("DD/App-missing-plist", workspace: nil)
            try f.file("DD/App-malformed/info.plist", "not a plist")
            #expect(one.derivedDataStores(under: [f.root + "/DD"]) == [new, old])
            let two = try #require(ProjectLayout.discover(paths: [f.root + "/Two"]))
            #expect(two.derivedDataStores(under: [f.root + "/DD"]).count == 1)
        }
    }

    @Test func `explicit derivedDataPath works directly and never takes another worktrees metadata`() throws {
        try fixture { f in
            try f.file("Repo/Package.swift")
            let layout = try #require(ProjectLayout.discover(paths: [f.root + "/Repo"]))
            let store = try f.store("CustomBuild", workspace: nil)
            #expect(layout.derivedDataStores(under: [f.root + "/CustomBuild", f.root + "/CustomBuild"]) == [store])
            _ = try f.store("OtherBuild", workspace: f.root + "/Other/App.xcodeproj")
            #expect(layout.derivedDataStores(under: [f.root + "/OtherBuild"]).isEmpty)
        }
    }
    @Test func `oversized DerivedData metadata is refused before decoding`() throws {
        try fixture { f in
            try f.file("Repo/.git", "gitdir: elsewhere")
            try f.file("Repo/App.xcodeproj/project.pbxproj")
            let layout = try #require(ProjectLayout.discover(paths: [f.root + "/Repo"]))
            _ = try f.store("DD/App-large", workspace: layout.containers[0])
            let data = try PropertyListSerialization.data(
                fromPropertyList: [
                    "WorkspacePath": layout.containers[0], "Padding": String(repeating: "x", count: 1 << 20),
                ], format: .binary, options: 0)
            try data.write(to: URL(fileURLWithPath: f.root + "/DD/App-large/info.plist"))
            #expect(layout.derivedDataStores(under: [f.root + "/DD"]).isEmpty)
        }
    }

    @Test func `missing access dates use directory mtime and symlink spellings match canonical containers`() throws {
        try fixture { f in
            try f.file("Repo/.git", "gitdir: elsewhere")
            try f.file("Repo/App.xcodeproj/project.pbxproj")
            try FileManager.default.createSymbolicLink(atPath: f.root + "/Link", withDestinationPath: f.root + "/Repo")
            let layout = try #require(ProjectLayout.discover(paths: [f.root + "/Link"]))
            #expect(layout.root == f.root + "/Repo")
            var expected: [String] = []
            for (name, date) in [("new", 20.0), ("old", 10.0)] {
                expected.append(try f.store("DD/" + name, workspace: nil))
                let data = try PropertyListSerialization.data(
                    fromPropertyList: [
                        "WorkspacePath": f.root + "/Link/App.xcodeproj"
                    ], format: .xml, options: 0)
                try data.write(to: URL(fileURLWithPath: f.root + "/DD/" + name + "/info.plist"))
                try FileManager.default.setAttributes(
                    [.modificationDate: Date(timeIntervalSince1970: date)],
                    ofItemAtPath: f.root + "/DD/" + name)
            }
            #expect(layout.derivedDataStores(under: [f.root + "/DD"]) == expected)
        }
    }

}
