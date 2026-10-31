//  deadwood's standard-library trims (its `Support/StringTrimming.swift`), so the collectors spell types as deadwood
//  does without linking corelibs Foundation.

extension String {
    /// Equivalent of `trimmingCharacters(in: .whitespaces)`: spaces and horizontal tabs, not newlines.
    var trimmedHorizontalWhitespace: String {
        let isHorizontal: (Character) -> Bool = { $0 == " " || $0 == "\t" }
        return String(self.drop(while: isHorizontal).reversed().drop(while: isHorizontal).reversed())
    }

    /// Equivalent of `trimmingCharacters(in: .whitespacesAndNewlines)`.
    var trimmedWhitespaceAndNewlines: String {
        String(self.drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed())
    }
}
