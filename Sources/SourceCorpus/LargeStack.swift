#if canImport(Darwin)
    internal import Darwin
#elseif canImport(Glibc)
    internal import Glibc
#endif

/// Runs work on a thread with a large stack (analyzerkit roadmap 0041).
///
/// swift-syntax's location converter and every syntax visitor recurse once per level of the tree, and a long method chain
/// nests one level per link. On the small stacks of the cooperative pool (512 KiB) a file of a few thousand chained calls
/// overflowed the stack and killed the whole run.
public enum LargeStack {
    /// The stack the per-file work gets. Reserved, not committed: only the pages a deep file touches are used.
    public static let defaultSize = 256 << 20

    /// Runs `body` on a fresh thread whose stack is `stackSize` bytes, and returns its result.
    public static func run<R: Sendable>(stackSize: Int = defaultSize, _ body: @escaping @Sendable () -> R) async -> R {
        body()
    }
}
