import Foundation
import Testing

@testable import ProjectModel

/// A temporary project tree: files, manifests, and Xcode projects written as `project.pbxproj` text.
struct ProjectFixture {
    let root: String

    static func with(_ body: (ProjectFixture) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "classify-\(UUID().uuidString)")
            .resolvingSymlinksInPath().path
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        // A repository boundary, so the layout stops here and not at `/`.
        try FileManager.default.createDirectory(atPath: root + "/.git", withIntermediateDirectories: true)
        try body(ProjectFixture(root: root))
    }

    /// Writes `content` at `name` under the root and returns the absolute path.
    @discardableResult
    func file(_ name: String, _ content: String = "let x = 1\n") throws -> String {
        let url = URL(fileURLWithPath: root + "/" + name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    func path(_ name: String) -> String { root + "/" + name }

    /// The classification of the layout around every file written so far.
    func classification(of paths: [String]) throws -> ProjectClassification {
        let layout = try #require(ProjectLayout.discover(paths: paths))
        return ProjectClassification.load(layout)
    }
}

/// An Xcode project, built object by object and rendered the way Xcode writes it: tabs, `/* comments */`, bare words
/// where Xcode leaves them bare, quotes and escapes elsewhere.
struct XcodeFixture {
    private var objects: [(id: String, isa: String, fields: [(String, Value)])] = []
    private var targetIDs: [String: String] = [:]
    private var mainChildren: [String] = []
    private var targetList: [String] = []
    private var counter = 0

    enum Value {
        case string(String)
        case list([String])
    }

    private mutating func newID() -> String {
        counter += 1
        let digits = String(counter, radix: 16, uppercase: true)
        return "AB" + String(repeating: "0", count: 22 - digits.count) + digits
    }

    /// The id of the target named `name`, assigned on first use so exceptions can name targets declared later.
    mutating func targetID(_ name: String) -> String {
        if let id = targetIDs[name] { return id }
        let id = newID()
        targetIDs[name] = id
        return id
    }

    /// A synchronized folder at `path` under the main group, with membership exceptions per target name.
    mutating func folder(_ path: String, exceptions: [(target: String, files: [String])] = []) -> String {
        var exceptionIDs: [String] = []
        for exception in exceptions {
            let id = newID()
            objects.append(
                (
                    id, "PBXFileSystemSynchronizedBuildFileExceptionSet",
                    [("membershipExceptions", .list(exception.files)), ("target", .string(targetID(exception.target)))]
                ))
            exceptionIDs.append(id)
        }
        let id = newID()
        var fields: [(String, Value)] = [("path", .string(path)), ("sourceTree", .string("<group>"))]
        if !exceptionIDs.isEmpty { fields.insert(("exceptions", .list(exceptionIDs)), at: 0) }
        objects.append((id, "PBXFileSystemSynchronizedRootGroup", fields))
        mainChildren.append(id)
        return id
    }

    /// A file reference; `sourceTree` is `<group>` unless given.
    mutating func reference(_ path: String, sourceTree: String = "<group>") -> String {
        let id = newID()
        objects.append(
            (
                id, "PBXFileReference",
                [
                    ("lastKnownFileType", .string("sourcecode.swift")), ("path", .string(path)),
                    ("sourceTree", .string(sourceTree)),
                ]
            ))
        return id
    }

    /// A group at `path` holding `children`; under the main group when `top`.
    mutating func group(_ path: String?, children: [String], top: Bool = true) -> String {
        let id = newID()
        var fields: [(String, Value)] = [("children", .list(children)), ("sourceTree", .string("<group>"))]
        if let path { fields.append(("path", .string(path))) }
        objects.append((id, "PBXGroup", fields))
        if top { mainChildren.append(id) }
        return id
    }

    /// A run-script phase.
    mutating func script(_ name: String, _ text: String, inputs: [String] = [], outputs: [String] = []) -> String {
        let id = newID()
        objects.append(
            (
                id, "PBXShellScriptBuildPhase",
                [
                    ("buildActionMask", .string("2147483647")), ("inputPaths", .list(inputs)), ("name", .string(name)),
                    ("outputPaths", .list(outputs)), ("shellPath", .string("/bin/sh")), ("shellScript", .string(text)),
                ]
            ))
        return id
    }

    /// A native target with synchronized folders, explicitly listed sources (file reference ids) and extra phases.
    mutating func target(
        _ name: String, type: String, folders: [String] = [], sources: [String] = [], phases: [String] = []
    ) {
        var buildFiles: [String] = []
        for reference in sources {
            let id = newID()
            objects.append((id, "PBXBuildFile", [("fileRef", .string(reference))]))
            buildFiles.append(id)
        }
        let sourcesPhase = newID()
        objects.append(
            (
                sourcesPhase, "PBXSourcesBuildPhase",
                [("buildActionMask", .string("2147483647")), ("files", .list(buildFiles))]
            ))
        let id = targetID(name)
        var fields: [(String, Value)] = [
            ("buildPhases", .list(phases + [sourcesPhase])), ("name", .string(name)),
            ("productName", .string(name)), ("productType", .string(type)),
        ]
        if !folders.isEmpty { fields.insert(("fileSystemSynchronizedGroups", .list(folders)), at: 1) }
        objects.append((id, "PBXNativeTarget", fields))
        targetList.append(id)
    }

    /// The `project.pbxproj` text.
    mutating func render() -> String {
        let main = newID()
        objects.append((main, "PBXGroup", [("children", .list(mainChildren)), ("sourceTree", .string("<group>"))]))
        let project = newID()
        objects.append(
            (
                project, "PBXProject",
                [
                    ("compatibilityVersion", .string("Xcode 14.0")), ("mainGroup", .string(main)),
                    ("projectDirPath", .string("")), ("projectRoot", .string("")), ("targets", .list(targetList)),
                ]
            ))
        var text =
            "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 77;\n\tobjects = {\n"
        for object in objects.sorted(by: { $0.isa < $1.isa || ($0.isa == $1.isa && $0.id < $1.id) }) {
            text += "\t\t\(object.id) /* \(object.isa) */ = {\n\t\t\tisa = \(object.isa);\n"
            for (key, value) in object.fields {
                switch value {
                case .string(let string): text += "\t\t\t\(key) = \(Self.quoted(string));\n"
                case .list(let items):
                    text += "\t\t\t\(key) = (\n"
                    for item in items { text += "\t\t\t\t\(Self.quoted(item)) /* item */,\n" }
                    text += "\t\t\t);\n"
                }
            }
            text += "\t\t};\n"
        }
        text += "\t};\n\trootObject = \(project) /* Project object */;\n}\n"
        return text
    }

    /// Bare when Xcode would leave it bare, quoted and escaped otherwise.
    static func quoted(_ value: String) -> String {
        let bare =
            !value.isEmpty
            && value.unicodeScalars.allSatisfy {
                ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0)
                    || "_$/:.-".unicodeScalars.contains($0)
            }
        if bare { return value }
        var escaped = "\""
        for character in value {
            switch character {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\n": escaped += "\\n"
            case "\t": escaped += "\\t"
            default: escaped.append(character)
            }
        }
        return escaped + "\""
    }
}

extension ProjectFixture {
    /// Writes `xcode` as `<name>.xcodeproj/project.pbxproj` under `directory` (the root when empty).
    func project(_ name: String, _ xcode: XcodeFixture, in directory: String = "") throws {
        var xcode = xcode
        let prefix = directory.isEmpty ? "" : directory + "/"
        try file(prefix + name + ".xcodeproj/project.pbxproj", xcode.render())
    }
}

enum ProductType {
    static let application = "com.apple.product-type.application"
    static let framework = "com.apple.product-type.framework"
    static let appExtension = "com.apple.product-type.app-extension"
    static let unitTest = "com.apple.product-type.bundle.unit-test"
    static let uiTest = "com.apple.product-type.bundle.ui-testing"
}
