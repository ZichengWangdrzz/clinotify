import XCTest
@testable import CLINotifyShared

final class CodexNotifyAdapterTests: XCTestCase {
    func testAgentTurnCompleteMapsToDone() {
        let event = CodexNotifyAdapter.event(
            from: #"{"type":"agent-turn-complete","turn-id":"turn-123","cwd":"/tmp/work","message":"finished"}"#,
            tty: "ttys001",
            cwd: "/fallback"
        )

        XCTAssertEqual(event.source, .codex)
        XCTAssertEqual(event.type, .done)
        XCTAssertEqual(event.tty, "ttys001")
        XCTAssertEqual(event.cwd, "/tmp/work")
        XCTAssertEqual(event.session, "turn-123")
        XCTAssertEqual(event.title, "finished")
    }

    func testApprovalLikeEventMapsToAttention() {
        let event = CodexNotifyAdapter.event(
            from: #"{"type":"exec-approval-requested","turn_id":"turn-456","summary":"approval needed"}"#,
            tty: "ttys002",
            cwd: "/repo"
        )

        XCTAssertEqual(event.type, .attention)
        XCTAssertEqual(event.session, "turn-456")
        XCTAssertEqual(event.title, "approval needed")
        XCTAssertEqual(event.cwd, "/repo")
    }
}
