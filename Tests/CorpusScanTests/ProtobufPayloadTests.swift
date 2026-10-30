import AemiProtobuf
import AemiProtobufCore
import CorpusScan
import Foundation
import Testing

/// A facts type on the protobuf payload path (roadmap 0017), written with the field helpers the tools use.
struct ProtoSample: Sendable, Equatable, Codable, AemiProtoFastEncodable, AemiProtoFastDecodable {
    enum Kind: String, Sendable, Codable { case plain, special }

    struct Child: Sendable, Equatable, Codable, AemiProtoFastEncodable, AemiProtoFastDecodable {
        var line = 0

        func __aepbEncode(into writer: inout WireWriter) throws(WireError) { writer.field(1, line) }

        static func __aepbDecode(from reader: inout WireReader) throws(WireError) -> Self {
            var child = Self()
            try reader.forEachField { tag, reader throws(WireError) in
                switch tag.fieldNumber {
                case 1: child.line = try reader.readInt()
                default: try reader.skipField(tag)
                }
            }
            return child
        }
    }

    var name = ""
    var note: String? = nil
    var offset = 0
    var flag = false
    var kind = Kind.plain
    var tags: [String] = []
    var children: [Child] = []
    var child: Child? = nil
    var wide: UInt64 = 0

    func __aepbEncode(into writer: inout WireWriter) throws(WireError) {
        writer.field(1, name)
        writer.field(2, note)
        writer.field(3, offset)
        writer.field(4, flag)
        writer.field(5, kind)
        writer.field(6, tags)
        try writer.field(7, children)
        try writer.field(8, child)
        writer.field(9, wide)
    }

    static func __aepbDecode(from reader: inout WireReader) throws(WireError) -> Self {
        var sample = Self()
        try reader.forEachField { tag, reader throws(WireError) in
            switch tag.fieldNumber {
            case 1: sample.name = try reader.readString()
            case 2: sample.note = try reader.readString()
            case 3: sample.offset = try reader.readInt()
            case 4: sample.flag = try reader.readBool()
            case 5: sample.kind = try reader.readEnum(Kind.self)
            case 6: sample.tags.append(try reader.readString())
            case 7: sample.children.append(try reader.readMessage(Child.self))
            case 8: sample.child = try reader.readMessage(Child.self)
            case 9: sample.wide = try reader.readVarint()
            default: try reader.skipField(tag)
            }
        }
        return sample
    }
}

struct JSONOnlySample: Codable, Sendable { var name: String }

@Suite struct ProtobufPayloadTests {
    private static func roundTrip(_ sample: ProtoSample) throws -> ProtoSample {
        try ProtobufDecoder().decode(ProtoSample.self, fromBytes: ProtobufEncoder().encodeToBytes(sample))
    }

    @Test func `every helper round-trips, and default values take no bytes but an enumeration's`() throws {
        let full = ProtoSample(
            name: "n", note: "", offset: -42, flag: true, kind: .special, tags: ["a", "", "b"],
            children: [.init(line: 3), .init(line: 0)], child: .init(line: 0), wide: .max)
        #expect(try Self.roundTrip(full) == full)
        // An enumeration has no default case to leave out, so it is the one field a default value writes.
        var onlyKind = WireWriter()
        onlyKind.field(5, ProtoSample.Kind.plain)
        #expect(try ProtobufEncoder().encodeToBytes(ProtoSample()) == onlyKind.bytes)
        #expect(try Self.roundTrip(ProtoSample()) == ProtoSample())
        #expect(try Self.roundTrip(ProtoSample(note: nil)).note == nil, "nil stays apart from an empty string")
    }

    @Test func `an unknown enumeration value fails the decode`() throws {
        var writer = WireWriter()
        writer.appendTag(5, .lengthDelimited)
        writer.appendString("unheard-of")
        #expect(throws: (any Error).self) { try ProtobufDecoder().decode(ProtoSample.self, fromBytes: writer.bytes) }
    }

    /// A type that is both `Codable` and fast protobuf is stored as protobuf: the shards hold no JSON key.
    @Test func `a protobuf facts type is cached as protobuf and served warm`() async throws {
        try await Scratch.withAsync { scratch in
            let h = Harness(scratch: scratch)
            let a = try h.settled("A.swift", "alpha")
            let b = try h.settled("B.swift", "beta")
            func scan() async throws -> CorpusScan<ProtoSample> {
                try await CorpusScanner.scan(paths: [a, b], cache: h.location(), identity: h.identity) { path, bytes in
                    ProtoSample(name: String(decoding: bytes, as: UTF8.self), tags: [path])
                }
            }
            let cold = try await scan()
            let warm = try await scan()
            #expect(cold.cacheHits == 0)
            #expect(warm.cacheHits == 2)
            #expect(warm.files.map(\.facts) == cold.files.map(\.facts))
            let shards = (FileManager.default.subpaths(atPath: scratch.path("cache")) ?? []).filter {
                $0.hasSuffix(".shard")
            }
            let bytes = try shards.flatMap { try Data(contentsOf: URL(fileURLWithPath: scratch.path("cache/\($0)"))) }
            let text = String(decoding: bytes, as: UTF8.self)
            #expect(text.contains("alpha"))
            #expect(!text.contains("\"name\""), "a JSON payload")
        }
    }

    /// The codec is part of the cache key: a payload another codec wrote is never decoded.
    @Test func `a JSON payload under the same salt is a miss for the protobuf path`() async throws {
        try await Scratch.withAsync { scratch in
            let h = Harness(scratch: scratch)
            let a = try h.settled("A.swift", "alpha")
            _ = try await CorpusScanner.scan(paths: [a], cache: h.location(), identity: h.identity, salt: "s") {
                _, _ in JSONOnlySample(name: "x")
            }
            let proto: CorpusScan<ProtoSample> = try await CorpusScanner.scan(
                paths: [a], cache: h.location(), identity: h.identity, salt: "s"
            ) { _, _ in ProtoSample(name: "y") }
            #expect(proto.cacheHits == 0)
            #expect(proto.files.first?.facts?.name == "y")
        }
    }
}
