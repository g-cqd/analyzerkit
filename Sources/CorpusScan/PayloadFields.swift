public import AemiProtobuf
public import AemiProtobufCore

// Field helpers for facts written by hand on AemiProtobuf's wire (roadmap 0017): the tools' models keep their `let`s and
// their String-raw enumerations, which `@ProtoMessage` would have to change.
//
// The rules, as proto3's implicit presence: a scalar equal to its default (empty, zero, false) is not written, and a
// missing field decodes to the default; an `Optional` is written when it holds a value, so nil and an empty string stay
// apart; a repeated field writes one record per element. Integers are zigzag varints, so a negative one stays short.

extension WireWriter {
    public mutating func field(_ number: FieldNumber, _ value: String) {
        guard !value.isEmpty else { return }
        appendTag(number, .lengthDelimited)
        appendString(value)
    }

    public mutating func field(_ number: FieldNumber, _ value: String?) {
        guard let value else { return }
        appendTag(number, .lengthDelimited)
        appendString(value)
    }

    public mutating func field(_ number: FieldNumber, _ value: Int) {
        guard value != 0 else { return }
        appendTag(number, .varint)
        appendVarint(ZigZag.encode(Int64(value)))
    }

    public mutating func field(_ number: FieldNumber, _ value: Int?) {
        guard let value else { return }
        appendTag(number, .varint)
        appendVarint(ZigZag.encode(Int64(value)))
    }

    public mutating func field(_ number: FieldNumber, _ value: UInt64) {
        guard value != 0 else { return }
        appendTag(number, .varint)
        appendVarint(value)
    }

    public mutating func field(_ number: FieldNumber, _ value: Bool) {
        guard value else { return }
        appendTag(number, .varint)
        appendVarint(1)
    }

    public mutating func field(_ number: FieldNumber, _ value: Bool?) {
        guard let value else { return }
        appendTag(number, .varint)
        appendVarint(value ? 1 : 0)
    }

    /// A String-raw enumeration, as its raw value: a case added later never renumbers an older one.
    public mutating func field<E: RawRepresentable>(_ number: FieldNumber, _ value: E) where E.RawValue == String {
        appendTag(number, .lengthDelimited)
        appendString(value.rawValue)
    }

    public mutating func field<E: RawRepresentable>(_ number: FieldNumber, _ value: E?) where E.RawValue == String {
        guard let value else { return }
        field(number, value)
    }

    public mutating func field(_ number: FieldNumber, _ values: [String]) {
        for value in values {
            appendTag(number, .lengthDelimited)
            appendString(value)
        }
    }

    /// A nested message, written even when empty: its presence is the value.
    public mutating func field<M: AemiProtoFastEncodable>(_ number: FieldNumber, _ value: M) throws(WireError) {
        try appendMessage(field: number) { writer throws(WireError) in try value.__aepbEncode(into: &writer) }
    }

    public mutating func field<M: AemiProtoFastEncodable>(_ number: FieldNumber, _ value: M?) throws(WireError) {
        guard let value else { return }
        try field(number, value)
    }

    public mutating func field<M: AemiProtoFastEncodable>(_ number: FieldNumber, _ values: [M]) throws(WireError) {
        for value in values { try field(number, value) }
    }
}

extension WireReader {
    /// Calls `body` with each field's tag; `body` reads the value or skips it with `skipField`.
    public mutating func forEachField(
        _ body: (FieldTag, inout WireReader) throws(WireError) -> Void
    ) throws(WireError) {
        while let tag = try nextTag() { try body(tag, &self) }
    }

    /// A zigzag varint, as ``WireWriter/field(_:_:)-(_,Int)`` writes it.
    public mutating func readInt() throws(WireError) -> Int {
        Int(truncatingIfNeeded: ZigZag.decode(try readVarint()))
    }

    public mutating func readBool() throws(WireError) -> Bool { try readVarint() != 0 }

    /// A String-raw enumeration; a raw value this build does not know fails the decode, so the payload is a miss.
    public mutating func readEnum<E: RawRepresentable>(_: E.Type) throws(WireError) -> E where E.RawValue == String {
        let raw = try readString()
        guard let value = E(rawValue: raw) else { throw .missingRequired(path: "\(E.self).\(raw)") }
        return value
    }

    public mutating func readMessage<M: AemiProtoFastDecodable>(_: M.Type) throws(WireError) -> M {
        try readMessage { reader throws(WireError) in try M.__aepbDecode(from: &reader) }
    }
}
