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
}

/// Reads the OpenStep property-list grammar: `{ key = value; }`, `( a, b, )`, quoted and bare strings, `<hex data>`,
/// `//` and `/* */` comments. Red stub (roadmap 0043).
enum OpenStepPlist {
    static func parse(_ bytes: [UInt8]) -> PlistValue? {
        nil
    }
}
