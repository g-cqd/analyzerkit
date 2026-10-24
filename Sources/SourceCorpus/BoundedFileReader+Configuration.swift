#if canImport(FoundationEssentials)
    public import FoundationEssentials
#else
    public import Foundation
#endif

extension BoundedFileReader {
    /// Why a configuration-class file was not read, in the two kinds every analyzer reports.
    public enum ConfigurationFailure: Error, Equatable, Sendable {
        /// Not a regular file, or the system refused to open it; the text says which.
        case unreadable(String)
        /// Larger than the cap.
        case tooLarge(cap: Int)

        /// The detail an analyzer's `configurationInvalid` error carries for ``tooLarge(cap:)``.
        public var invalidDetail: String? {
            if case .tooLarge(let cap) = self { "exceeds \(cap) byte cap" } else { nil }
        }
    }

    /// Reads a small configuration-class file, stat first so a hostile or accidental giant JSON is rejected
    /// before it is read, and fails closed.
    ///
    /// The wording of an unreadable file is Foundation's, which the analyzers print: a missing path, a
    /// directory or a device reads as "not a regular file", and a regular file the system refuses reads as the
    /// error `Data(contentsOf:)` throws. ``read(path:cap:)`` is the faster read for source files, which have
    /// no such wording to keep.
    /// - Parameters:
    ///   - path: the file.
    ///   - cap: the largest size accepted, in bytes.
    /// - Throws: a ``ConfigurationFailure``.
    /// - Complexity: O(*n*) in the file size.
    public static func readConfiguration(path: String, cap: Int = configByteCap) throws(ConfigurationFailure) -> Data {
        // attributesOfItem, not URL resource values, which are corelibs-only; the caller canonicalizes paths, so
        // symlinks are already resolved here.
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        guard (attributes?[.type] as? FileAttributeType) == .typeRegular else {
            throw .unreadable("not a regular file")
        }
        if let size = attributes?[.size] as? Int, size > cap {
            throw .tooLarge(cap: cap)
        }
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw .unreadable(String(describing: error))
        }
        guard data.count <= cap else { throw .tooLarge(cap: cap) }
        return data
    }
}
