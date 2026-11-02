import AemiProcess
import Testing

@testable import IndexStoreSupport

/// Which processes a cleanup ends, decided from a process list (ADR-0030).
@Suite struct LeftoverSelectionTests {
    private func process(_ pid: Int32, session: Int32, started: Int64 = 100) -> ProcessTable.Process {
        ProcessTable.Process(pid: pid, parent: 1, group: pid, session: session, started: started)
    }

    @Test func `members of the child's session started since the launch are selected`() {
        let list = [process(501, session: 500), process(502, session: 500, started: 10), process(600, session: 600)]
        let selected = BoundedProcess.selectLeftovers(
            in: list,
            session: 500,
            since: 50,
            me: 10,
            mySession: 9,
            holdsToken: nil
        )
        #expect(selected.map(\.pid) == [501])
    }

    /// The child (pid 500) was reaped and its pid given to a new session leader: its number is someone else's now.
    @Test func `a session whose id is a live pid again is someone else's, and nothing is selected by it`() {
        let list = [process(500, session: 500, started: 900), process(501, session: 500, started: 901)]
        let selected = BoundedProcess.selectLeftovers(
            in: list,
            session: 500,
            since: 50,
            me: 10,
            mySession: 9,
            holdsToken: nil
        )
        #expect(selected.isEmpty)
    }

    @Test func `token holders are selected wherever they are, and this process never`() {
        let list = [process(700, session: 700), process(10, session: 9), process(701, session: 9)]
        let selected = BoundedProcess.selectLeftovers(
            in: list,
            session: nil,
            since: 50,
            me: 10,
            mySession: 9,
            holdsToken: { $0 == 700 || $0 == 10 }
        )
        #expect(selected.map(\.pid) == [700])
        // This process's own session is never a target.
        #expect(
            BoundedProcess.selectLeftovers(in: list, session: 9, since: 0, me: 10, mySession: 9, holdsToken: nil)
                .isEmpty
        )
    }
}
