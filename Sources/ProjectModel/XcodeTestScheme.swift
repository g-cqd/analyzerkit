internal import Foundation

/// A `PBXNativeTarget` of an Xcode project, as a scheme refers to it.
public struct XcodeNativeTarget: Sendable, Hashable {
    /// The target's object identifier in `project.pbxproj` (a scheme's `BlueprintIdentifier`).
    public let id: String
    public let name: String
    public let productName: String
    public let productType: String
    /// The `.xcodeproj` directory, absolute.
    public let project: String

    public init(id: String, name: String, productName: String, productType: String, project: String) {
        self.id = id
        self.name = name
        self.productName = productName
        self.productType = productType
        self.project = project
    }

    /// A unit-test bundle (`bundle.unit-test`, or the legacy `bundle.ocunit-test`).
    public var isUnitTest: Bool {
        productType == "com.apple.product-type.bundle.unit-test"
            || productType == "com.apple.product-type.bundle.ocunit-test"
    }

    /// A UI-test bundle.
    public var isUITest: Bool { productType == "com.apple.product-type.bundle.ui-testing" }
}

/// Reads the native targets of a project from its `project.pbxproj`, never running Xcode.
public enum XcodeNativeTargets {
    /// The targets of the `.xcodeproj` at `project`, in the project's order; nil when it cannot be read.
    public static func read(project: String) -> [XcodeNativeTarget]? {
        guard let data = FileManager.default.contents(atPath: project + "/project.pbxproj"),
            let root = OpenStepPlist.parse(Array(data))?.dictionary,
            let objects = root["objects"]?.dictionary, let rootID = root["rootObject"]?.string,
            let projectObject = objects[rootID]?.dictionary
        else { return nil }
        return (projectObject["targets"]?.strings ?? []).compactMap { id in
            guard let target = objects[id]?.dictionary, target["isa"]?.string == "PBXNativeTarget" else { return nil }
            let name = target["name"]?.string ?? id
            return XcodeNativeTarget(
                id: id,
                name: name,
                productName: target["productName"]?.string ?? name,
                productType: target["productType"]?.string ?? "",
                project: project
            )
        }
    }
}

/// Writes a shared scheme whose test action runs the given targets: what a tool generates when a workspace's own
/// schemes leave test targets out (a Tuist or Bazel workspace with dozens of modules).
public enum XcodeSchemeWriter {
    /// The `.xcscheme` XML building for testing and testing `targets`.
    /// - Parameter containerDirectory: the directory holding the project or workspace the scheme belongs to; each
    ///   target's project is referenced relative to it (`container:App.xcodeproj`), or by absolute path outside it.
    public static func testScheme(_ targets: [XcodeNativeTarget], containerDirectory: String) -> String {
        func reference(_ target: XcodeNativeTarget, indent: String) -> String {
            let container = containerReference(target.project, from: containerDirectory)
            return """
                \(indent)<BuildableReference
                \(indent)   BuildableIdentifier = "primary"
                \(indent)   BlueprintIdentifier = "\(escaped(target.id))"
                \(indent)   BuildableName = "\(escaped(target.productName)).xctest"
                \(indent)   BlueprintName = "\(escaped(target.name))"
                \(indent)   ReferencedContainer = "\(escaped(container))">
                \(indent)</BuildableReference>
                """
        }
        let entries = targets.map { target in
            """
                     <BuildActionEntry
                        buildForTesting = "YES"
                        buildForRunning = "NO"
                        buildForProfiling = "NO"
                        buildForArchiving = "NO"
                        buildForAnalyzing = "NO">
            \(reference(target, indent: "            "))
                     </BuildActionEntry>
            """
        }
        let testables = targets.map { target in
            """
                     <TestableReference
                        skipped = "NO">
            \(reference(target, indent: "            "))
                     </TestableReference>
            """
        }
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <Scheme
               LastUpgradeVersion = "1600"
               version = "1.7">
               <BuildAction
                  parallelizeBuildables = "YES"
                  buildImplicitDependencies = "YES">
                  <BuildActionEntries>
            \(entries.joined(separator: "\n"))
                  </BuildActionEntries>
               </BuildAction>
               <TestAction
                  buildConfiguration = "Debug"
                  selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
                  selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
                  shouldUseLaunchSchemeArgsEnv = "YES">
                  <Testables>
            \(testables.joined(separator: "\n"))
                  </Testables>
               </TestAction>
               <LaunchAction
                  buildConfiguration = "Debug"
                  launchStyle = "0"
                  debugDocumentVersioning = "YES"
                  allowLocationSimulation = "YES">
               </LaunchAction>
            </Scheme>

            """
    }

    /// `container:` and `path` relative to `directory` when inside it, else `absolute:` and `path` itself (Xcode
    /// joins a `container:` path to the directory even when it starts with `/`).
    private static func containerReference(_ path: String, from directory: String) -> String {
        let prefix = directory.hasSuffix("/") ? directory : directory + "/"
        return path.hasPrefix(prefix) ? "container:" + path.dropFirst(prefix.count) : "absolute:" + path
    }

    /// `text` with XML's five special characters escaped, for an attribute value.
    private static func escaped(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default: result.append(character)
            }
        }
        return result
    }
}
