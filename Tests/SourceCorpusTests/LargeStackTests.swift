import Testing

@testable import SourceCorpus

#if canImport(Darwin)
    import Darwin

    /// The size of the calling thread's stack. Darwin only: Glibc's `pthread_getattr_np` is a GNU extension Swift's
    /// Glibc module does not import.
    private func currentStackSize() -> Int {
        unsafe pthread_get_stacksize_np(pthread_self())
    }
#endif

struct LargeStackTests {
    #if canImport(Darwin)
        @Test func `the work runs on a stack of the size asked for`() async {
            let size = await LargeStack.run(stackSize: 64 << 20) { currentStackSize() }
            #expect(size >= 64 << 20, "ran on a stack of \(size) bytes")
        }
    #endif

    @Test func `the result comes back, and many runs can be in flight at once`() async {
        let results = await withTaskGroup(of: Int.self) { group in
            for value in 0..<64 { group.addTask { await LargeStack.run(stackSize: 8 << 20) { value * 2 } } }
            var collected: [Int] = []
            for await result in group { collected.append(result) }
            return collected.sorted()
        }
        #expect(results == (0..<64).map { $0 * 2 })
    }
}
