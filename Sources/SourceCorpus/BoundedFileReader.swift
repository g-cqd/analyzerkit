public import AemiIO

#if canImport(Darwin)
    internal import Darwin
#elseif canImport(Glibc)
    internal import Glibc
#endif

/// Reads one file whole, with a stat-first size cap so a hostile or accidental giant file cannot be pulled
/// into memory. Fails closed with a typed error.
public enum BoundedFileReader {
    /// Why a file was not read.
    public enum Failure: Error, Equatable, Sendable, CustomStringConvertible {
        /// Not a regular file (a directory, a device, a socket).
        case notRegularFile
        /// Larger than the cap, in bytes.
        case tooLarge(cap: Int)
        /// A system call failed.
        case io(IOError)

        public var description: String {
            switch self {
            case .notRegularFile: "not a regular file"
            case .tooLarge(let cap): "exceeds \(cap) byte cap"
            case .io(let error): error.description
            }
        }
    }

    /// 1 MiB: generous for configuration and baseline JSON, cheap to reject above.
    public static let configByteCap = 1 << 20

    /// 16 MiB: a Swift source file larger than this is generated or hostile.
    public static let sourceByteCap = 16 << 20

    /// The bytes of the regular file at `path`.
    ///
    /// One `open`, one `fstat` and one positioned read: the size checked is the size of the descriptor
    /// read, so the file cannot grow past the cap between the check and the read.
    /// - Parameters:
    ///   - path: the file.
    ///   - cap: the largest size accepted, in bytes.
    /// - Throws: a ``Failure``.
    /// - Complexity: O(*n*) in the file size, and one allocation of exactly that size.
    public static func read(path: String, cap: Int = configByteCap) throws(Failure) -> [UInt8] {
        do {
            let file = try PosixFile(path: path, mode: .readOnly)
            defer { file.close() }
            guard isRegularFile(file.fileDescriptor) else { throw Failure.notRegularFile }
            let size = try file.fileSize()
            guard size <= cap else { throw Failure.tooLarge(cap: cap) }
            var bytes = [UInt8](repeating: 0, count: size)
            try bytes.withUnsafeMutableBytes { buffer in try unsafe file.pread(into: buffer, at: 0) }
            return bytes
        } catch let failure as Failure {
            throw failure
        } catch let error as IOError {
            throw .io(error)
        } catch {
            throw .io(IOError(errno: 0, op: String(describing: error)))
        }
    }

    /// Whether `descriptor` is open on a regular file.
    private static func isRegularFile(_ descriptor: Int32) -> Bool {
        var status = stat()
        // The buffer is a local the call fills before returning; nothing escapes.
        guard unsafe fstat(descriptor, &status) == 0 else { return false }
        return status.st_mode & S_IFMT == S_IFREG
    }
}
