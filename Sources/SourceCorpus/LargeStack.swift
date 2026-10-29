#if canImport(Darwin)
    internal import Darwin
#elseif canImport(Glibc)
    internal import Glibc
#endif

/// Runs work on a thread with a large stack (analyzerkit roadmap 0041).
///
/// swift-syntax's location converter and every syntax visitor recurse once per level of the tree, and a long method chain
/// nests one level per link. On the small stacks of the cooperative pool (512 KiB) a file of a few thousand chained calls
/// overflowed the stack and killed the whole run. A detached POSIX thread with a stack of its own size runs the work and
/// hands the result back through a continuation, so no task blocks while it runs.
public enum LargeStack {
    /// The stack the per-file work gets. Reserved, not committed: only the pages a deep file touches are used.
    public static let defaultSize = 256 << 20

    /// Runs `body` on a fresh thread whose stack is at least `stackSize` bytes, and returns its result. If the system
    /// refuses a thread, `body` runs on the caller's thread instead, as it did before.
    public static func run<R: Sendable>(stackSize: Int = defaultSize, _ body: @escaping @Sendable () -> R) async -> R {
        await withCheckedContinuation { (continuation: CheckedContinuation<R, Never>) in
            let job = Job { continuation.resume(returning: body()) }
            if !spawn(job, stackSize: stackSize) { job.work() }
        }
    }

    /// The work a thread runs, kept alive across the C boundary by an unbalanced retain.
    private final class Job: Sendable {
        let work: @Sendable () -> Void
        init(_ work: @escaping @Sendable () -> Void) { self.work = work }
    }

    private static func spawn(_ job: Job, stackSize: Int) -> Bool {
        var attributes = pthread_attr_t()
        guard unsafe pthread_attr_init(&attributes) == 0 else { return false }
        defer { unsafe pthread_attr_destroy(&attributes) }
        let page = Int(getpagesize())
        let size = (max(stackSize, page) + page - 1) / page * page
        guard unsafe pthread_attr_setstacksize(&attributes, size) == 0,
            unsafe pthread_attr_setdetachstate(&attributes, Int32(PTHREAD_CREATE_DETACHED)) == 0
        else { return false }
        let context = unsafe Unmanaged.passRetained(job).toOpaque()
        #if canImport(Darwin)
            var thread: pthread_t?
            let status = unsafe pthread_create(&thread, &attributes, { unsafe LargeStack.start($0) }, context)
        #else
            var thread = pthread_t()
            let status = unsafe pthread_create(
                &thread, &attributes,
                { context in
                    guard let context = unsafe context else { return nil }
                    return unsafe LargeStack.start(context)
                }, context)
        #endif
        if status != 0 {
            unsafe Unmanaged<Job>.fromOpaque(context).release()
            return false
        }
        return true
    }

    /// The thread's entry: takes back the retained job and runs it.
    private static func start(_ context: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
        unsafe Unmanaged<Job>.fromOpaque(context).takeRetainedValue().work()
        return nil
    }
}
