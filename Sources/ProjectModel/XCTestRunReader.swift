public import Foundation

/// Reads Apple `.xctestrun` property lists (format v1 and v2, T-ECO-4) to discover testable bundles, product module
/// names, and skip/only test-identifier filters without invoking `xcodebuild`.
public struct XCTestRun: Sendable, Equatable {
    public struct TestTarget: Sendable, Equatable {
        public let blueprintName: String
        public let productModuleName: String?
        public let testBundlePath: String?
        public let testHostPath: String?
        public let onlyTestIdentifiers: [String]
        public let skipTestIdentifiers: [String]
    }

    public let formatVersion: Int
    public let targets: [TestTarget]
}

public enum XCTestRunReader {
    /// Parses raw `.xctestrun` XML/binary plist bytes into an `XCTestRun`. Returns `nil` when malformed.
    public static func read(_ data: Data) -> XCTestRun? {
        guard let root = unsafe (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        else {
            return nil
        }
        let metadata = root["__xctestrun_metadata__"] as? [String: Any]
        let version = (metadata?["FormatVersion"] as? Int) ?? 1

        var targets: [XCTestRun.TestTarget] = []
        if let configs = root["TestConfigurations"] as? [[String: Any]] {
            // Format v2: TestConfigurations[*].TestTargets[*]
            for config in configs {
                for entry in config["TestTargets"] as? [[String: Any]] ?? [] {
                    if let target = parseTarget(entry, fallbackName: nil) {
                        targets.append(target)
                    }
                }
            }
        } else {
            // Format v1: top-level dictionary entries excluding `__xctestrun_metadata__`
            for (key, value) in root.sorted(by: { $0.key < $1.key }) where key != "__xctestrun_metadata__" {
                guard let entry = value as? [String: Any] else { continue }
                if let target = parseTarget(entry, fallbackName: key) {
                    targets.append(target)
                }
            }
        }

        targets.sort { $0.blueprintName < $1.blueprintName }
        return XCTestRun(formatVersion: version, targets: targets)
    }

    private static func parseTarget(_ entry: [String: Any], fallbackName: String?) -> XCTestRun.TestTarget? {
        let name = (entry["BlueprintName"] as? String) ?? fallbackName
        guard let name, !name.isEmpty else { return nil }
        return XCTestRun.TestTarget(
            blueprintName: name,
            productModuleName: entry["ProductModuleName"] as? String,
            testBundlePath: entry["TestBundlePath"] as? String,
            testHostPath: entry["TestHostPath"] as? String,
            onlyTestIdentifiers: entry["OnlyTestIdentifiers"] as? [String] ?? [],
            skipTestIdentifiers: entry["SkipTestIdentifiers"] as? [String] ?? []
        )
    }
}
