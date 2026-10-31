//  Lifted from SwiftStaticAnalysis (MIT) — Models/SourceLocation.swift, by way of deadwood (analyzerkit roadmap
//  0055); renamed from `SourceLocation`, which SwiftSyntax also declares.

// MARK: - SymbolLocation

/// A location within a source file (1-indexed line/column).
public struct SymbolLocation: Sendable, Hashable, Codable {
    /// The file path.
    public let file: String

    /// Line number (1-indexed).
    public let line: Int

    /// Column number (1-indexed).
    public let column: Int

    /// Byte offset from start of file.
    public let offset: Int

    public init(file: String, line: Int, column: Int, offset: Int = 0) {
        self.file = file
        self.line = line
        self.column = column
        self.offset = offset
    }
}

// MARK: - SymbolRange

/// A range of source code.
public struct SymbolRange: Sendable, Hashable, Codable {
    /// Start location.
    public let start: SymbolLocation

    /// End location.
    public let end: SymbolLocation

    public init(start: SymbolLocation, end: SymbolLocation) {
        self.start = start
        self.end = end
    }
}
