/// The SARIF 2.1.0 subset the analyzers write, one model for all of them (roadmap 0011). Optional members are omitted
/// when nil, so a tool that never sets one writes the bytes it always wrote; each tool keeps its own encoder.
public enum Sarif {
    public struct Text: Encodable, Sendable, Equatable {
        public let text: String
        public init(_ text: String) { self.text = text }
    }

    /// A property value: a string, or a list of strings (rule tags).
    public enum Property: Encodable, Sendable, Equatable {
        case string(String)
        case strings([String])

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value): try container.encode(value)
            case .strings(let values): try container.encode(values)
            }
        }
    }

    public struct ArtifactLocation: Encodable, Sendable, Equatable {
        public let uri: String
        public let uriBaseId: String?

        /// `path` as the report spells it, through ``ArtifactURI``.
        public init(path: String, root: String?) {
            (uri, uriBaseId) = ArtifactURI.location(of: path, root: root)
        }

        public init(uri: String, uriBaseId: String? = nil) {
            self.uri = uri
            self.uriBaseId = uriBaseId
        }
    }

    public struct Region: Encodable, Sendable, Equatable {
        public let startLine: Int
        public let startColumn: Int?
        public init(startLine: Int, startColumn: Int?) {
            self.startLine = startLine
            self.startColumn = startColumn
        }
    }

    public struct PhysicalLocation: Encodable, Sendable, Equatable {
        public let artifactLocation: ArtifactLocation
        public let region: Region
        public init(artifactLocation: ArtifactLocation, region: Region) {
            self.artifactLocation = artifactLocation
            self.region = region
        }
    }

    public struct Location: Encodable, Sendable, Equatable {
        public let physicalLocation: PhysicalLocation
        public let message: Text?
        public init(physicalLocation: PhysicalLocation, message: Text? = nil) {
            self.physicalLocation = physicalLocation
            self.message = message
        }
    }

    public struct ThreadFlowLocation: Encodable, Sendable, Equatable {
        public let location: Location
        public init(location: Location) { self.location = location }
    }

    public struct ThreadFlow: Encodable, Sendable, Equatable {
        public let locations: [ThreadFlowLocation]
        public init(locations: [ThreadFlowLocation]) { self.locations = locations }
    }

    public struct CodeFlow: Encodable, Sendable, Equatable {
        public let threadFlows: [ThreadFlow]
        public init(threadFlows: [ThreadFlow]) { self.threadFlows = threadFlows }
    }

    public struct Result: Encodable, Sendable, Equatable {
        public let ruleId: String
        public let level: String
        public let message: Text
        public let locations: [Location]
        public let relatedLocations: [Location]?
        /// An empty array is written as `[]`; nil omits the key.
        public let codeFlows: [CodeFlow]?
        public let partialFingerprints: [String: String]
        public let properties: [String: Property]?

        public init(
            ruleId: String, level: String, message: Text, locations: [Location], relatedLocations: [Location]? = nil,
            codeFlows: [CodeFlow]? = nil, partialFingerprints: [String: String], properties: [String: Property]? = nil
        ) {
            self.ruleId = ruleId
            self.level = level
            self.message = message
            self.locations = locations
            self.relatedLocations = relatedLocations
            self.codeFlows = codeFlows
            self.partialFingerprints = partialFingerprints
            self.properties = properties
        }
    }

    public struct Rule: Encodable, Sendable, Equatable {
        public let id: String
        public let shortDescription: Text
        public let fullDescription: Text?
        public let help: Text?
        public let defaultConfiguration: [String: String]?
        public let properties: [String: Property]?

        public init(
            id: String, shortDescription: Text, fullDescription: Text? = nil, help: Text? = nil,
            defaultConfiguration: [String: String]? = nil, properties: [String: Property]? = nil
        ) {
            self.id = id
            self.shortDescription = shortDescription
            self.fullDescription = fullDescription
            self.help = help
            self.defaultConfiguration = defaultConfiguration
            self.properties = properties
        }
    }

    public struct Driver: Encodable, Sendable, Equatable {
        public let name: String
        public let version: String
        public let informationUri: String
        public let rules: [Rule]
        public init(name: String, version: String, informationUri: String, rules: [Rule]) {
            self.name = name
            self.version = version
            self.informationUri = informationUri
            self.rules = rules
        }
    }

    public struct Tool: Encodable, Sendable, Equatable {
        public let driver: Driver
        public init(driver: Driver) { self.driver = driver }
    }

    public struct Notification: Encodable, Sendable, Equatable {
        public let level: String
        public let message: Text
        public init(level: String, message: Text) {
            self.level = level
            self.message = message
        }
    }

    /// Whether the run produced a result a consumer may trust: a failure is an error notification, which SARIF
    /// defines as a failed run whose results are incomplete (§3.20.21); warnings never fail it.
    public struct Invocation: Encodable, Sendable, Equatable {
        public let executionSuccessful: Bool
        public let toolExecutionNotifications: [Notification]?

        public init(failure: String?, warnings: [String] = []) {
            executionSuccessful = failure == nil
            let notifications =
                (failure.map { [Notification(level: "error", message: Text($0))] } ?? [])
                + warnings.map { Notification(level: "warning", message: Text($0)) }
            toolExecutionNotifications = notifications.isEmpty ? nil : notifications
        }
    }

    public struct Run: Encodable, Sendable, Equatable {
        public let tool: Tool
        public let invocations: [Invocation]?
        /// The absolute URI of ``ArtifactURI/baseID`` that relative uris resolve against; nil without a root.
        public let originalUriBaseIds: [String: ArtifactLocation]?
        /// The unit every region's columns count in; see ``SarifColumns``.
        public let columnKind = "utf16CodeUnits"
        public let results: [Result]

        public init(tool: Tool, invocations: [Invocation]?, root: String?, results: [Result]) {
            self.tool = tool
            self.invocations = invocations
            originalUriBaseIds = root.map {
                [ArtifactURI.baseID: ArtifactLocation(uri: ArtifactURI.baseURI(of: $0))]
            }
            self.results = results
        }
    }

    public struct Log: Encodable, Sendable, Equatable {
        public let version = "2.1.0"
        public let schema = "https://json.schemastore.org/sarif-2.1.0.json"
        public let runs: [Run]

        private enum CodingKeys: String, CodingKey {
            case version
            case schema = "$schema"
            case runs
        }

        public init(runs: [Run]) { self.runs = runs }
    }
}
