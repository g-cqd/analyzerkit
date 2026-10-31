import CorpusScan
import Foundation
import SourceCorpus
import Synchronization
import Testing

// Darwin only: reading the current thread's stack size on Linux needs Glibc's `pthread_getattr_np`, a GNU extension
// Swift's Glibc module does not import.
#if canImport(Darwin)
    import Darwin

    /// The smallest stack any extraction ran on.
    private final class SmallestStack: Sendable {
        private let storage = Mutex(Int.max)
        func record() {
            let size = unsafe pthread_get_stacksize_np(pthread_self())
            storage.withLock { $0 = min($0, size) }
        }
        var value: Int { storage.withLock { $0 } }
    }

    /// Extraction parses and walks a syntax tree, which recurses once per level: it runs on the large stack, so one deeply
    /// nested file cannot overflow the scan (analyzerkit roadmap 0041).
    @Suite struct LargeStackScanTests {
        @Test func `every extraction runs on the large stack`() async throws {
            try await Scratch.withAsync { scratch in
                let paths = try (0..<8).map { try scratch.write("F\($0).swift", "let x = \($0)") }
                let smallest = SmallestStack()
                _ = try await CorpusScanner.scan(paths: paths) { _, _ in
                    smallest.record()
                    return SampleFacts(names: [])
                }
                #expect(smallest.value >= LargeStack.defaultSize, "an extraction ran on \(smallest.value) bytes")
            }
        }
    }
#endif
