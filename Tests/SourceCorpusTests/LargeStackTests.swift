import Testing

@testable import SourceCorpus

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

/// The size of the calling thread's stack.
private func currentStackSize() -> Int {
    #if canImport(Darwin)
        return unsafe pthread_get_stacksize_np(pthread_self())
    #else
        var attributes = pthread_attr_t()
        guard unsafe pthread_getattr_np(pthread_self(), &attributes) == 0 else { return 0 }
        defer { unsafe pthread_attr_destroy(&attributes) }
        var size = 0
        unsafe pthread_attr_getstacksize(&attributes, &size)
        return size
    #endif
}

struct LargeStackTests {
    @Test func `the work runs on a stack of the size asked for`() async {
        let size = await LargeStack.run(stackSize: 64 << 20) { currentStackSize() }
        #expect(size >= 64 << 20, "ran on a stack of \(size) bytes")
    }

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
