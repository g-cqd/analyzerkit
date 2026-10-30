internal import AemiJSON
internal import AemiProtobuf

/// How a scan turns facts into the payload bytes a shard keeps, and back. A payload that does not decode is a miss.
struct PayloadCodec<Facts: Sendable>: Sendable {
    let encode: @Sendable (Facts) -> [UInt8]?
    let decode: @Sendable ([UInt8]) -> Facts?

    /// Mixed into the salt of the protobuf path, so a JSON payload under the same salt is never decoded as protobuf.
    static var protobufSalt: String { "\u{0}payload=protobuf" }
}

extension PayloadCodec where Facts: Codable {
    /// AemiJSON: the macro path for `@JSONCodable` facts, the generic one for the rest.
    static var json: Self {
        Self(
            encode: { try? AemiJSON.JSONEncoder().encodeToBytes($0) },
            decode: { try? AemiJSON.JSONDecoder().decode(Facts.self, from: $0) })
    }
}

extension PayloadCodec where Facts: AemiProtoFastEncodable & AemiProtoFastDecodable {
    /// AemiProtobuf's fast path (roadmap 0017).
    static var protobuf: Self {
        Self(
            encode: { try? ProtobufEncoder().encodeToBytes($0) },
            decode: { try? ProtobufDecoder().decode(Facts.self, fromBytes: $0) })
    }
}
