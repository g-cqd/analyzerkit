/// What an Xcode project says about its files: which targets compile what, and what its run-script phases write and
/// run. Paths are absolute and lexically standard.
struct XcodeProjectModel: Sendable, Equatable {
    struct Target: Sendable, Equatable {
        var name: String
        var productType: String
    }

    /// A path that puts the files at or under it into a target, minus the excluded paths at or under which they lie.
    struct Membership: Sendable, Equatable {
        var target: Int
        var excluded: [String]
    }

    var targets: [Target]
    /// Keyed by the file or directory the membership covers.
    var memberships: [String: [Membership]]
    /// Files a run-script phase writes, with the phase's name.
    var outputs: [String: String]
    /// Swift files a run-script phase runs, with the phase's name.
    var scripts: [String: String]
}

/// Reads `project.pbxproj` (ADR-0024 item 3).
enum XcodeProjectReader {
    enum Reading: Sendable, Equatable {
        case project(XcodeProjectModel)
        case unknown(String)
    }

    static let testProductTypes: Set<String> = [
        "com.apple.product-type.bundle.unit-test", "com.apple.product-type.bundle.ui-testing",
        "com.apple.product-type.bundle.ocunit-test",
    ]

    /// Reads the project whose `project.pbxproj` holds `bytes`; `container` is the `.xcodeproj` directory.
    static func read(_ bytes: [UInt8], container: String) -> Reading {
        guard let root = OpenStepPlist.parse(bytes)?.dictionary else {
            return .unknown("project.pbxproj does not parse")
        }
        guard let objects = root["objects"]?.dictionary, let rootID = root["rootObject"]?.string,
            let project = objects[rootID]?.dictionary
        else { return .unknown("project.pbxproj has no project object") }
        var parentDirectory = ProjectPaths.parent(container)
        if let relative = project["projectDirPath"]?.string, !relative.isEmpty {
            parentDirectory = ProjectPaths.join(parentDirectory, relative)
        }
        let paths = ReferencePaths(objects: objects, projectDirectory: parentDirectory)

        var model = XcodeProjectModel(targets: [], memberships: [:], outputs: [:], scripts: [:])
        var targetIndex: [String: Int] = [:]
        var foldersOwned: [String: [Int]] = [:]
        for targetID in project["targets"]?.strings ?? [] {
            guard let target = objects[targetID]?.dictionary, target["isa"]?.string == "PBXNativeTarget" else {
                continue
            }
            let index = model.targets.count
            targetIndex[targetID] = index
            model.targets.append(
                .init(name: target["name"]?.string ?? targetID, productType: target["productType"]?.string ?? ""))
            for folder in target["fileSystemSynchronizedGroups"]?.strings ?? [] {
                foldersOwned[folder, default: []].append(index)
            }
            for phaseID in target["buildPhases"]?.strings ?? [] {
                guard let phase = objects[phaseID]?.dictionary else { continue }
                switch phase["isa"]?.string {
                case "PBXSourcesBuildPhase":
                    for buildFileID in phase["files"]?.strings ?? [] {
                        guard let reference = objects[buildFileID]?.dictionary?["fileRef"]?.string,
                            let path = paths.resolve(reference)
                        else { continue }
                        model.memberships[path, default: []].append(.init(target: index, excluded: []))
                    }
                case "PBXShellScriptBuildPhase":
                    record(phase, into: &model, projectDirectory: parentDirectory)
                default: continue
                }
            }
        }
        // Synchronized folders: a folder's files belong to the targets owning it; an exception set flips membership for
        // its target, removing a file from an owner and adding it to any other target.
        for (folderID, object) in objects
        where object.dictionary?["isa"]?.string == "PBXFileSystemSynchronizedRootGroup" {
            guard let folder = object.dictionary, let directory = paths.resolve(folderID) else { continue }
            let owners = foldersOwned[folderID] ?? []
            var flipped: [Int: [String]] = [:]
            for exceptionID in folder["exceptions"]?.strings ?? [] {
                guard let exception = objects[exceptionID]?.dictionary,
                    exception["isa"]?.string == "PBXFileSystemSynchronizedBuildFileExceptionSet",
                    let targetID = exception["target"]?.string, let target = targetIndex[targetID]
                else { continue }
                let files = (exception["membershipExceptions"]?.strings ?? []).map { ProjectPaths.join(directory, $0) }
                flipped[target, default: []].append(contentsOf: files)
            }
            for owner in owners {
                model.memberships[directory, default: []].append(.init(target: owner, excluded: flipped[owner] ?? []))
            }
            for (target, files) in flipped where !owners.contains(target) {
                for file in files { model.memberships[file, default: []].append(.init(target: target, excluded: [])) }
            }
        }
        return .project(model)
    }

    /// A run-script phase's Swift outputs and the Swift files its script names.
    private static func record(
        _ phase: [String: PlistValue], into model: inout XcodeProjectModel, projectDirectory: String
    ) {
        let name = phase["name"]?.string ?? "Run Script"
        for output in phase["outputPaths"]?.strings ?? [] {
            guard let path = ProjectPaths.expand(output, projectDirectory: projectDirectory), path.hasSuffix(".swift")
            else {
                continue
            }
            model.outputs[path] = name
        }
        let script = phase["shellScript"]?.string ?? ""
        for word in ProjectPaths.swiftWords(in: script) {
            guard let path = ProjectPaths.expand(word, projectDirectory: projectDirectory) else { continue }
            model.scripts[path] = name
        }
    }
}

/// Resolves file references and groups to absolute paths through their parents and source trees.
private struct ReferencePaths {
    let objects: [String: PlistValue]
    let projectDirectory: String
    let parents: [String: String]

    init(objects: [String: PlistValue], projectDirectory: String) {
        self.objects = objects
        self.projectDirectory = projectDirectory
        var parents: [String: String] = [:]
        for (id, object) in objects {
            guard let children = object.dictionary?["children"]?.strings else { continue }
            for child in children { parents[child] = id }
        }
        self.parents = parents
    }

    /// The absolute path of a reference or group; nil when it lies in a build-products tree or another source tree
    /// this reader does not know, or when its chain of parents is broken.
    func resolve(_ id: String, depth: Int = 0) -> String? {
        guard depth < 64, let object = objects[id]?.dictionary else { return nil }
        let path = object["path"]?.string ?? ""
        switch object["sourceTree"]?.string ?? "<group>" {
        case "<absolute>": return ProjectPaths.join("/", path)
        case "SOURCE_ROOT": return ProjectPaths.join(projectDirectory, path)
        case "<group>":
            guard let parent = parents[id] else { return ProjectPaths.join(projectDirectory, path) }
            guard let base = resolve(parent, depth: depth + 1) else { return nil }
            return ProjectPaths.join(base, path)
        default: return nil
        }
    }
}

/// Lexical path arithmetic: no file-system access, so the reader is pure.
enum ProjectPaths {
    static func parent(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "." }
        return slash == path.startIndex ? "/" : String(path[..<slash])
    }

    /// `relative` against `base` (unless absolute), with `.` and `..` collapsed and no trailing separator.
    static func join(_ base: String, _ relative: String) -> String {
        let combined = relative.hasPrefix("/") ? relative : base + "/" + relative
        var components: [Substring] = []
        for component in combined.split(separator: "/") {
            switch component {
            case ".": continue
            case "..": if !components.isEmpty { components.removeLast() }
            default: components.append(component)
            }
        }
        return "/" + components.joined(separator: "/")
    }

    static let projectDirectorySettings = ["SRCROOT", "PROJECT_DIR", "SOURCE_ROOT"]

    /// `path` with the project-directory build settings replaced, made absolute against the project directory; nil
    /// when another build setting is left in it.
    static func expand(_ path: String, projectDirectory: String) -> String? {
        var expanded = path
        for setting in projectDirectorySettings {
            for spelling in ["$(\(setting))", "${\(setting)}", "$\(setting)"] {
                expanded = expanded.replacing(spelling, with: projectDirectory)
            }
        }
        guard !expanded.contains("$") else { return nil }
        return join(projectDirectory, expanded)
    }

    /// The words of a shell script that name a Swift file, unquoted.
    static func swiftWords(in script: String) -> [String] {
        var words: [String] = []
        var current = ""
        func flush() {
            if current.hasSuffix(".swift") { words.append(current) }
            current = ""
        }
        for character in script {
            if character.isWhitespace || character == ";" || character == "|" || character == "&" || character == "("
                || character == ")"
            {
                flush()
            } else if character != "\"" && character != "'" {
                current.append(character)
            }
        }
        flush()
        return words
    }
}
