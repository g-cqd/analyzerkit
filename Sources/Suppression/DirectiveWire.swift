//  The protobuf form of a directive in the tools' facts payloads: arcleak's, deadwood's and dolly's identical copies
//  moved here. Field numbers are the format: never renumber one.
//
//    1  a rule's raw value, repeated, sorted and without repeats (a rule set has no order)
//    2  the kind's name
//    3  the line
//    4  the reason, left out when there is none

public import AemiProtobuf
public import AemiProtobufCore
import CorpusScan

extension Directive: AemiProtoRequiredFields where Rule: RawRepresentable, Rule.RawValue == String {}

extension Directive: AemiProtoFastEncodable where Rule: RawRepresentable, Rule.RawValue == String {
    public func __aepbEncode(into writer: inout WireWriter) throws(WireError) {
        for raw in Set(rules.map(\.rawValue)).sorted() { writer.field(1, raw) }
        writer.field(2, kind)
        writer.field(3, line)
        writer.field(4, reason)
    }
}

extension Directive: AemiProtoFastDecodable where Rule: RawRepresentable, Rule.RawValue == String {
    public static func __aepbDecode(from reader: inout WireReader) throws(WireError) -> Self {
        var rules: [Rule] = []
        var kind = DirectiveKind.accept
        var line = 0
        var reason: String?
        try reader.forEachField { tag, reader throws(WireError) in
            switch tag.fieldNumber {
            case 1:
                let rule = try reader.readEnum(Rule.self)
                if !rules.contains(rule) { rules.append(rule) }
            case 2: kind = try reader.readEnum(DirectiveKind.self)
            case 3: line = try reader.readInt()
            case 4: reason = try reader.readString()
            default: try reader.skipField(tag)
            }
        }
        return Self(rules: rules, kind: kind, line: line, reason: reason)
    }
}
