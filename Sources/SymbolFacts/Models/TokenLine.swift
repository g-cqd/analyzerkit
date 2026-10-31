// MARK: - TokenLine

/// An identifier-shaped token found in a string literal, with its line.
public struct TokenLine: Sendable, Hashable, Codable {
    public let token: String
    public let line: Int

    public init(token: String, line: Int) {
        self.token = token
        self.line = line
    }
}
