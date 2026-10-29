/// A value of an OpenStep ("old-style ASCII") property list, the format of `project.pbxproj`.
enum PlistValue: Sendable, Equatable {
    case string(String)
    case array([PlistValue])
    case dictionary([String: PlistValue])
    case data([UInt8])

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var array: [PlistValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var dictionary: [String: PlistValue]? {
        if case .dictionary(let value) = self { return value }
        return nil
    }

    /// The strings of an array value; nil when it is not an array of strings.
    var strings: [String]? {
        guard let array else { return nil }
        var result: [String] = []
        result.reserveCapacity(array.count)
        for item in array {
            guard let string = item.string else { return nil }
            result.append(string)
        }
        return result
    }
}

/// Reads the OpenStep property-list grammar: `{ key = value; }`, `( a, b, )`, quoted and bare strings, `<hex data>`,
/// `//` and `/* */` comments. Anything else, and anything after the root value, refuses the whole input (ADR-0024).
///
/// Nesting is bounded (``maximumDepth``) so a hostile file cannot exhaust the stack; a project nests four levels.
enum OpenStepPlist {
    static let maximumDepth = 64

    static func parse(_ bytes: [UInt8]) -> PlistValue? {
        var parser = Parser(bytes: bytes)
        guard let value = parser.value(depth: 0) else { return nil }
        parser.skipTrivia()
        return parser.offset == bytes.count && !parser.failed ? value : nil
    }

    private struct Parser {
        let bytes: [UInt8]
        var offset = 0
        var failed = false

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        mutating func skipTrivia() {
            while offset < bytes.count {
                let byte = bytes[offset]
                if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
                    offset += 1
                } else if byte == UInt8(ascii: "/"), offset + 1 < bytes.count, bytes[offset + 1] == UInt8(ascii: "/") {
                    while offset < bytes.count, bytes[offset] != 0x0A { offset += 1 }
                } else if byte == UInt8(ascii: "/"), offset + 1 < bytes.count, bytes[offset + 1] == UInt8(ascii: "*") {
                    offset += 2
                    while offset + 1 < bytes.count,
                        !(bytes[offset] == UInt8(ascii: "*") && bytes[offset + 1] == UInt8(ascii: "/"))
                    {
                        offset += 1
                    }
                    guard offset + 1 < bytes.count else {
                        failed = true
                        offset = bytes.count
                        return
                    }
                    offset += 2
                } else {
                    return
                }
            }
        }

        /// Takes `byte` after any trivia, or fails.
        mutating func expect(_ byte: UInt8) -> Bool {
            skipTrivia()
            guard !failed, offset < bytes.count, bytes[offset] == byte else { return false }
            offset += 1
            return true
        }

        mutating func value(depth: Int) -> PlistValue? {
            skipTrivia()
            guard !failed, offset < bytes.count, depth < OpenStepPlist.maximumDepth else { return nil }
            switch bytes[offset] {
            case UInt8(ascii: "{"):
                offset += 1
                return dictionary(depth: depth)
            case UInt8(ascii: "("):
                offset += 1
                return array(depth: depth)
            case UInt8(ascii: "<"):
                offset += 1
                return data()
            case UInt8(ascii: "\""):
                offset += 1
                return quoted().map(PlistValue.string)
            default:
                return bare().map(PlistValue.string)
            }
        }

        mutating func dictionary(depth: Int) -> PlistValue? {
            var result: [String: PlistValue] = [:]
            while true {
                skipTrivia()
                guard !failed, offset < bytes.count else { return nil }
                if bytes[offset] == UInt8(ascii: "}") {
                    offset += 1
                    return .dictionary(result)
                }
                guard case .string(let key) = value(depth: depth + 1), expect(UInt8(ascii: "=")),
                    let item = value(depth: depth + 1), expect(UInt8(ascii: ";"))
                else { return nil }
                result[key] = item
            }
        }

        mutating func array(depth: Int) -> PlistValue? {
            var result: [PlistValue] = []
            while true {
                skipTrivia()
                guard !failed, offset < bytes.count else { return nil }
                if bytes[offset] == UInt8(ascii: ")") {
                    offset += 1
                    return .array(result)
                }
                guard let item = value(depth: depth + 1) else { return nil }
                result.append(item)
                skipTrivia()
                guard offset < bytes.count else { return nil }
                if bytes[offset] == UInt8(ascii: ",") {
                    offset += 1
                } else if bytes[offset] != UInt8(ascii: ")") {
                    return nil
                }
            }
        }

        mutating func data() -> PlistValue? {
            var result: [UInt8] = []
            var high: UInt8?
            while offset < bytes.count {
                let byte = bytes[offset]
                offset += 1
                if byte == UInt8(ascii: ">") { return high == nil ? .data(result) : nil }
                if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D { continue }
                guard let nibble = Self.nibble(byte) else { return nil }
                if let first = high {
                    result.append(first << 4 | nibble)
                    high = nil
                } else {
                    high = nibble
                }
            }
            return nil
        }

        static func nibble(_ byte: UInt8) -> UInt8? {
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
            default: nil
            }
        }

        /// A quoted string after its opening quote. Escapes: `\n \t \r \" \\ \'`, `\Uxxxx`, octal `\ooo`; any other
        /// escaped character stands for itself.
        mutating func quoted() -> String? {
            var scalars = String.UnicodeScalarView()
            var start = offset
            var pending: [UInt8] = []
            while offset < bytes.count {
                let byte = bytes[offset]
                if byte == UInt8(ascii: "\"") {
                    pending.append(contentsOf: bytes[start..<offset])
                    offset += 1
                    scalars.append(contentsOf: String(decoding: pending, as: UTF8.self).unicodeScalars)
                    return String(scalars)
                }
                guard byte == UInt8(ascii: "\\") else {
                    offset += 1
                    continue
                }
                pending.append(contentsOf: bytes[start..<offset])
                offset += 1
                guard offset < bytes.count else { return nil }
                let escaped = bytes[offset]
                offset += 1
                switch escaped {
                case UInt8(ascii: "n"): pending.append(0x0A)
                case UInt8(ascii: "t"): pending.append(0x09)
                case UInt8(ascii: "r"): pending.append(0x0D)
                case UInt8(ascii: "U"):
                    var code: UInt32 = 0
                    for _ in 0..<4 {
                        guard offset < bytes.count, let nibble = Self.nibble(bytes[offset]) else { return nil }
                        code = code << 4 | UInt32(nibble)
                        offset += 1
                    }
                    guard let scalar = Unicode.Scalar(code) else { return nil }
                    pending.append(contentsOf: Array(String(Character(scalar)).utf8))
                case UInt8(ascii: "0")...UInt8(ascii: "7"):
                    var code = UInt32(escaped - UInt8(ascii: "0"))
                    for _ in 0..<2
                    where offset < bytes.count && (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(bytes[offset]) {
                        code = code << 3 | UInt32(bytes[offset] - UInt8(ascii: "0"))
                        offset += 1
                    }
                    guard code < 0x80 else { return nil }
                    pending.append(UInt8(code))
                default: pending.append(escaped)
                }
                start = offset
            }
            return nil
        }

        /// A bare word: letters, digits and `_ $ / : . - +`, plus `(`/`)` inside a `$(…)` build-setting reference.
        mutating func bare() -> String? {
            let start = offset
            var references = 0
            while offset < bytes.count {
                let byte = bytes[offset]
                let isWord =
                    (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
                    || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
                    || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || "_$/:.-+".utf8.contains(byte)
                if isWord {
                    offset += 1
                } else if byte == UInt8(ascii: "("), offset > start, bytes[offset - 1] == UInt8(ascii: "$") {
                    references += 1
                    offset += 1
                } else if byte == UInt8(ascii: ")"), references > 0 {
                    references -= 1
                    offset += 1
                } else {
                    break
                }
            }
            guard offset > start, references == 0 else { return nil }
            return String(decoding: bytes[start..<offset], as: UTF8.self)
        }
    }
}
