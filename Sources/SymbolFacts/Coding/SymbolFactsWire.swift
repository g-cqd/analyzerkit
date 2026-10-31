//  The protobuf coding of the facts (roadmap 0055), deadwood's facts-cache coding (its `Cache/FactsProtobufCoding.swift`,
//  roadmap 0017) moved here with the models, so deadwood's cache and any other reader agree on one format.
//
//  Field numbers are the format: never renumber one, and give a new field a new number. A location's file is left out
//  when it is the file the facts describe, which is nearly always.

public import AemiProtobuf
public import AemiProtobufCore
import CorpusScan

extension FileSymbolFacts: AemiProtoFastEncodable, AemiProtoFastDecodable {
    public func __aepbEncode(into writer: inout WireWriter) throws(WireError) {
        let file = file
        writer.field(1, file)
        for declaration in declarations {
            try writer.appendMessage(field: 2) { writer throws(WireError) in
                try SymbolFactsWire.write(declaration, file: file, into: &writer)
            }
        }
        for declaration in imports {
            try writer.appendMessage(field: 3) { writer throws(WireError) in
                try SymbolFactsWire.write(declaration, file: file, into: &writer)
            }
        }
        for reference in references {
            try writer.appendMessage(field: 4) { writer throws(WireError) in
                try SymbolFactsWire.write(reference, file: file, into: &writer)
            }
        }
        for scope in scopes {
            try writer.appendMessage(field: 5) { writer throws(WireError) in
                try SymbolFactsWire.write(scope, file: file, into: &writer)
            }
        }
        for token in stringLiteralTokens.sorted(by: { ($0.token, $0.line) < ($1.token, $1.line) }) {
            try writer.appendMessage(field: 6) { writer throws(WireError) in SymbolFactsWire.write(token, into: &writer)
            }
        }
        writer.field(7, commentTokens.sorted())
    }

    public static func __aepbDecode(from reader: inout WireReader) throws(WireError) -> Self {
        var file = ""
        var declarations: [Declaration] = []
        var imports: [Declaration] = []
        var references: [Reference] = []
        var scopes: [Scope] = []
        var strings: Set<TokenLine> = []
        var comments: Set<String> = []
        try reader.forEachField { tag, reader throws(WireError) in
            let known = file
            switch tag.fieldNumber {
            case 1: file = try reader.readString()
            case 2:
                declarations.append(
                    try reader.readMessage { reader throws(WireError) in
                        try SymbolFactsWire.readDeclaration(&reader, file: known)
                    })
            case 3:
                imports.append(
                    try reader.readMessage { reader throws(WireError) in
                        try SymbolFactsWire.readDeclaration(&reader, file: known)
                    })
            case 4:
                references.append(
                    try reader.readMessage { reader throws(WireError) in
                        try SymbolFactsWire.readReference(&reader, file: known)
                    })
            case 5:
                scopes.append(
                    try reader.readMessage { reader throws(WireError) in
                        try SymbolFactsWire.readScope(&reader, file: known)
                    })
            case 6:
                strings.insert(
                    try reader.readMessage { reader throws(WireError) in try SymbolFactsWire.readTokenLine(&reader) })
            case 7: comments.insert(try reader.readString())
            default: try reader.skipField(tag)
            }
        }
        return Self(
            file: file, declarations: declarations, imports: imports, references: references, scopes: scopes,
            stringLiteralTokens: strings, commentTokens: comments)
    }
}

/// The messages of ``FileSymbolFacts``, for a payload that embeds them: each location-bearing one takes the file the
/// facts describe, which its locations then leave out.
public enum SymbolFactsWire {
    // MARK: Locations

    public static func write(_ location: SymbolLocation, file: String, into writer: inout WireWriter) {
        if location.file != file { writer.field(1, location.file) }
        writer.field(2, location.line)
        writer.field(3, location.column)
        writer.field(4, location.offset)
    }

    public static func readLocation(_ reader: inout WireReader, file: String) throws(WireError) -> SymbolLocation {
        var path = file
        var line = 0
        var column = 0
        var offset = 0
        try reader.forEachField { tag, reader throws(WireError) in
            switch tag.fieldNumber {
            case 1: path = try reader.readString()
            case 2: line = try reader.readInt()
            case 3: column = try reader.readInt()
            case 4: offset = try reader.readInt()
            default: try reader.skipField(tag)
            }
        }
        return SymbolLocation(file: path, line: line, column: column, offset: offset)
    }

    private static func location(
        _ field: FieldNumber, _ location: SymbolLocation, file: String, into writer: inout WireWriter
    ) throws(WireError) {
        try writer.appendMessage(field: field) { writer throws(WireError) in write(location, file: file, into: &writer)
        }
    }

    // MARK: Scopes

    public static func write(_ scope: Scope, file: String, into writer: inout WireWriter) throws(WireError) {
        writer.field(1, scope.id.id)
        writer.field(2, scope.kind)
        writer.field(3, scope.name)
        writer.field(4, scope.parent?.id)
        try location(5, scope.location, file: file, into: &writer)
    }

    public static func readScope(_ reader: inout WireReader, file: String) throws(WireError) -> Scope {
        var id = ""
        var kind = ScopeKind.global
        var name: String?
        var parent: String?
        var location = SymbolLocation(file: file, line: 0, column: 0)
        try reader.forEachField { tag, reader throws(WireError) in
            switch tag.fieldNumber {
            case 1: id = try reader.readString()
            case 2: kind = try reader.readEnum(ScopeKind.self)
            case 3: name = try reader.readString()
            case 4: parent = try reader.readString()
            case 5:
                location = try reader.readMessage { reader throws(WireError) in try readLocation(&reader, file: file) }
            default: try reader.skipField(tag)
            }
        }
        return Scope(id: ScopeID(id), kind: kind, name: name, parent: parent.map(ScopeID.init), location: location)
    }

    // MARK: Declarations

    public static func write(_ declaration: Declaration, file: String, into writer: inout WireWriter) throws(WireError)
    {
        writer.field(1, declaration.name)
        writer.field(2, declaration.kind)
        writer.field(3, declaration.accessLevel)
        writer.field(4, UInt64(declaration.modifiers.rawValue))
        try location(5, declaration.location, file: file, into: &writer)
        try writer.appendMessage(field: 6) { writer throws(WireError) in
            try location(1, declaration.range.start, file: file, into: &writer)
            try location(2, declaration.range.end, file: file, into: &writer)
        }
        writer.field(7, declaration.scope.id)
        writer.field(8, declaration.typeAnnotation)
        writer.field(9, declaration.genericParameters)
        if let signature = declaration.signature {
            try writer.appendMessage(field: 10) { writer throws(WireError) in try write(signature, into: &writer) }
        }
        writer.field(11, declaration.documentation)
        for wrapper in declaration.propertyWrappers {
            try writer.appendMessage(field: 12) { writer throws(WireError) in
                writer.field(1, wrapper.kind)
                writer.field(2, wrapper.attributeText)
                writer.field(3, wrapper.arguments)
            }
        }
        if let info = declaration.swiftUIInfo {
            try writer.appendMessage(field: 13) { writer throws(WireError) in
                for conformance in info.conformances.sorted(by: { $0.rawValue < $1.rawValue }) {
                    writer.field(1, conformance)
                }
            }
        }
        writer.field(14, declaration.conformances)
        writer.field(15, declaration.attributes)
        try location(16, declaration.nameLocation, file: file, into: &writer)
    }

    public static func readDeclaration(_ reader: inout WireReader, file: String) throws(WireError) -> Declaration {
        var name = ""
        var kind = DeclarationKind.function
        var access = AccessLevel.internal
        var modifiers: UInt64 = 0
        var location = SymbolLocation(file: file, line: 0, column: 0)
        var range = SymbolRange(start: location, end: location)
        var scope = ""
        var typeAnnotation: String?
        var generics: [String] = []
        var signature: FunctionSignature?
        var documentation: String?
        var wrappers: [PropertyWrapperInfo] = []
        var swiftUI: SwiftUITypeInfo?
        var conformances: [String] = []
        var attributes: [String] = []
        var nameLocation: SymbolLocation?
        try reader.forEachField { tag, reader throws(WireError) in
            switch tag.fieldNumber {
            case 1: name = try reader.readString()
            case 2: kind = try reader.readEnum(DeclarationKind.self)
            case 3: access = try reader.readEnum(AccessLevel.self)
            case 4: modifiers = try reader.readVarint()
            case 5:
                location = try reader.readMessage { reader throws(WireError) in try readLocation(&reader, file: file) }
            case 6:
                range = try reader.readMessage { reader throws(WireError) in
                    var start = SymbolLocation(file: file, line: 0, column: 0)
                    var end = start
                    try reader.forEachField { tag, reader throws(WireError) in
                        switch tag.fieldNumber {
                        case 1:
                            start = try reader.readMessage { reader throws(WireError) in
                                try readLocation(&reader, file: file)
                            }
                        case 2:
                            end = try reader.readMessage { reader throws(WireError) in
                                try readLocation(&reader, file: file)
                            }
                        default: try reader.skipField(tag)
                        }
                    }
                    return SymbolRange(start: start, end: end)
                }
            case 7: scope = try reader.readString()
            case 8: typeAnnotation = try reader.readString()
            case 9: generics.append(try reader.readString())
            case 10: signature = try reader.readMessage { reader throws(WireError) in try readSignature(&reader) }
            case 11: documentation = try reader.readString()
            case 12:
                wrappers.append(
                    try reader.readMessage { reader throws(WireError) in
                        var kind = PropertyWrapperKind.unknown
                        var text = ""
                        var arguments: String?
                        try reader.forEachField { tag, reader throws(WireError) in
                            switch tag.fieldNumber {
                            case 1: kind = try reader.readEnum(PropertyWrapperKind.self)
                            case 2: text = try reader.readString()
                            case 3: arguments = try reader.readString()
                            default: try reader.skipField(tag)
                            }
                        }
                        return PropertyWrapperInfo(kind: kind, attributeText: text, arguments: arguments)
                    })
            case 13:
                swiftUI = try reader.readMessage { reader throws(WireError) in
                    var conformances: Set<SwiftUIConformance> = []
                    try reader.forEachField { tag, reader throws(WireError) in
                        switch tag.fieldNumber {
                        case 1: conformances.insert(try reader.readEnum(SwiftUIConformance.self))
                        default: try reader.skipField(tag)
                        }
                    }
                    return SwiftUITypeInfo(conformances: conformances)
                }
            case 14: conformances.append(try reader.readString())
            case 15: attributes.append(try reader.readString())
            case 16:
                nameLocation = try reader.readMessage { reader throws(WireError) in
                    try readLocation(&reader, file: file)
                }
            default: try reader.skipField(tag)
            }
        }
        return Declaration(
            name: name, kind: kind, accessLevel: access,
            modifiers: DeclarationModifiers(rawValue: UInt32(truncatingIfNeeded: modifiers)), location: location,
            nameLocation: nameLocation, range: range, scope: ScopeID(scope), typeAnnotation: typeAnnotation,
            genericParameters: generics,
            signature: signature, documentation: documentation, propertyWrappers: wrappers, swiftUIInfo: swiftUI,
            conformances: conformances, attributes: attributes)
    }

    public static func write(_ signature: FunctionSignature, into writer: inout WireWriter) throws(WireError) {
        for parameter in signature.parameters {
            try writer.appendMessage(field: 1) { writer throws(WireError) in
                writer.field(1, parameter.label)
                writer.field(2, parameter.name)
                writer.field(3, parameter.type)
                writer.field(4, parameter.hasDefaultValue)
                writer.field(5, parameter.isVariadic)
                writer.field(6, parameter.isInout)
            }
        }
        writer.field(2, signature.returnType)
        writer.field(3, signature.isAsync)
        writer.field(4, signature.isThrowing)
        writer.field(5, signature.isRethrowing)
    }

    public static func readSignature(_ reader: inout WireReader) throws(WireError) -> FunctionSignature {
        var parameters: [FunctionSignature.Parameter] = []
        var returnType: String?
        var isAsync = false
        var isThrowing = false
        var isRethrowing = false
        try reader.forEachField { tag, reader throws(WireError) in
            switch tag.fieldNumber {
            case 1:
                parameters.append(
                    try reader.readMessage { reader throws(WireError) in
                        var label: String?
                        var name = ""
                        var type = ""
                        var hasDefault = false
                        var isVariadic = false
                        var isInout = false
                        try reader.forEachField { tag, reader throws(WireError) in
                            switch tag.fieldNumber {
                            case 1: label = try reader.readString()
                            case 2: name = try reader.readString()
                            case 3: type = try reader.readString()
                            case 4: hasDefault = try reader.readBool()
                            case 5: isVariadic = try reader.readBool()
                            case 6: isInout = try reader.readBool()
                            default: try reader.skipField(tag)
                            }
                        }
                        return FunctionSignature.Parameter(
                            label: label, name: name, type: type, hasDefaultValue: hasDefault, isVariadic: isVariadic,
                            isInout: isInout)
                    })
            case 2: returnType = try reader.readString()
            case 3: isAsync = try reader.readBool()
            case 4: isThrowing = try reader.readBool()
            case 5: isRethrowing = try reader.readBool()
            default: try reader.skipField(tag)
            }
        }
        return FunctionSignature(
            parameters: parameters, returnType: returnType, isAsync: isAsync, isThrowing: isThrowing,
            isRethrowing: isRethrowing)
    }

    // MARK: References

    /// A reference whole. Fields 1 to 6 are what deadwood's cache keeps of one (name, line, context, qualifier, call
    /// labels), so its compact form reads as this one with the rest at their defaults: column 0, the file scope.
    public static func write(_ reference: Reference, file: String, into writer: inout WireWriter) throws(WireError) {
        writer.field(1, reference.identifier)
        writer.field(2, reference.location.line)
        writer.field(3, reference.context)
        writer.field(4, reference.qualifier)
        if let labels = reference.callLabels {
            writer.field(5, true)
            writer.field(6, labels)
        }
        writer.field(7, reference.location.column)
        writer.field(8, reference.location.offset)
        writer.field(9, reference.scope.id)
        writer.field(10, reference.isQualified == (reference.qualifier != nil) ? nil : reference.isQualified)
        if let name = reference.nameLocation { try location(11, name, file: file, into: &writer) }
        if reference.location.file != file { writer.field(12, reference.location.file) }
    }

    public static func readReference(_ reader: inout WireReader, file: String) throws(WireError) -> Reference {
        var identifier = ""
        var line = 0
        var context = ReferenceContext.unknown
        var qualifier: String?
        var hasLabels = false
        var labels: [String] = []
        var column = 0
        var offset = 0
        var scope = ScopeID.global
        var isQualified: Bool?
        var nameLocation: SymbolLocation?
        var path = file
        try reader.forEachField { tag, reader throws(WireError) in
            switch tag.fieldNumber {
            case 1: identifier = try reader.readString()
            case 2: line = try reader.readInt()
            case 3: context = try reader.readEnum(ReferenceContext.self)
            case 4: qualifier = try reader.readString()
            case 5: hasLabels = try reader.readBool()
            case 6: labels.append(try reader.readString())
            case 7: column = try reader.readInt()
            case 8: offset = try reader.readInt()
            case 9: scope = ScopeID(try reader.readString())
            case 10: isQualified = try reader.readBool()
            case 11:
                nameLocation = try reader.readMessage { reader throws(WireError) in
                    try readLocation(&reader, file: file)
                }
            case 12: path = try reader.readString()
            default: try reader.skipField(tag)
            }
        }
        return Reference(
            identifier: identifier, location: SymbolLocation(file: path, line: line, column: column, offset: offset),
            scope: scope, context: context, isQualified: isQualified ?? (qualifier != nil), qualifier: qualifier,
            callLabels: hasLabels ? labels : nil, nameLocation: nameLocation)
    }

    // MARK: String-literal tokens

    public static func write(_ token: TokenLine, into writer: inout WireWriter) {
        writer.field(1, token.token)
        writer.field(2, token.line)
    }

    public static func readTokenLine(_ reader: inout WireReader) throws(WireError) -> TokenLine {
        var token = ""
        var line = 0
        try reader.forEachField { tag, reader throws(WireError) in
            switch tag.fieldNumber {
            case 1: token = try reader.readString()
            case 2: line = try reader.readInt()
            default: try reader.skipField(tag)
            }
        }
        return TokenLine(token: token, line: line)
    }
}
