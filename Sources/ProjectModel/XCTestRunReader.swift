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
    private struct Metadata: Decodable {
        let formatVersion: Int?

        enum CodingKeys: String, CodingKey {
            case formatVersion = "FormatVersion"
        }
    }

    private struct RawTarget: Decodable {
        let blueprintName: String?
        let productModuleName: String?
        let testBundlePath: String?
        let testHostPath: String?
        let onlyTestIdentifiers: [String]?
        let skipTestIdentifiers: [String]?

        enum CodingKeys: String, CodingKey {
            case blueprintName = "BlueprintName"
            case productModuleName = "ProductModuleName"
            case testBundlePath = "TestBundlePath"
            case testHostPath = "TestHostPath"
            case onlyTestIdentifiers = "OnlyTestIdentifiers"
            case skipTestIdentifiers = "SkipTestIdentifiers"
        }
    }

    private struct RawConfig: Decodable {
        let testTargets: [RawTarget]?

        enum CodingKeys: String, CodingKey {
            case testTargets = "TestTargets"
        }
    }

    private struct V2Root: Decodable {
        let metadata: Metadata?
        let testConfigurations: [RawConfig]?

        enum CodingKeys: String, CodingKey {
            case metadata = "__xctestrun_metadata__"
            case testConfigurations = "TestConfigurations"
        }
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) {
            self.intValue = intValue
            self.stringValue = String(intValue)
        }
    }

    private struct V1Root: Decodable {
        let targets: [XCTestRun.TestTarget]

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicKey.self)
            var found: [XCTestRun.TestTarget] = []
            for key in container.allKeys where key.stringValue != "__xctestrun_metadata__" {
                guard let raw = try? container.decode(RawTarget.self, forKey: key) else { continue }
                let name = raw.blueprintName ?? key.stringValue
                guard !name.isEmpty else { continue }
                found.append(
                    XCTestRun.TestTarget(
                        blueprintName: name,
                        productModuleName: raw.productModuleName,
                        testBundlePath: raw.testBundlePath,
                        testHostPath: raw.testHostPath,
                        onlyTestIdentifiers: raw.onlyTestIdentifiers ?? [],
                        skipTestIdentifiers: raw.skipTestIdentifiers ?? []
                    )
                )
            }
            targets = found
        }
    }

    /// Parses raw `.xctestrun` XML/binary plist bytes into an `XCTestRun` using `PropertyListDecoder` (pure Swift
    /// `FoundationEssentials` on Linux and macOS, avoiding `libFoundation` `CFError` leaks under LSan).
    public static func read(_ data: Data) -> XCTestRun? {
        guard !data.isEmpty, let header = try? PropertyListDecoder().decode(V2Root.self, from: data) else {
            return nil
        }
        let version = header.metadata?.formatVersion ?? 1
        var targets: [XCTestRun.TestTarget] = []
        if let configs = header.testConfigurations {
            for config in configs {
                for raw in config.testTargets ?? [] {
                    guard let name = raw.blueprintName, !name.isEmpty else { continue }
                    targets.append(
                        XCTestRun.TestTarget(
                            blueprintName: name,
                            productModuleName: raw.productModuleName,
                            testBundlePath: raw.testBundlePath,
                            testHostPath: raw.testHostPath,
                            onlyTestIdentifiers: raw.onlyTestIdentifiers ?? [],
                            skipTestIdentifiers: raw.skipTestIdentifiers ?? []
                        )
                    )
                }
            }
        } else if let v1 = try? PropertyListDecoder().decode(V1Root.self, from: data) {
            targets = v1.targets
        }
        targets.sort { $0.blueprintName < $1.blueprintName }
        return XCTestRun(formatVersion: version, targets: targets)
    }
}
