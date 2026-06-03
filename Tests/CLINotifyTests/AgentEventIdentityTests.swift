import Foundation
import XCTest
@testable import CLINotifyShared

/// Locks the toast-identity invariants from ADR-0002: one toast per AGENT SESSION (never per tty), so
/// reused ttys can't bleed one session's toast into another, and a Claude and a Codex session can never
/// collide.
final class AgentEventIdentityTests: XCTestCase {
    private func event(
        source: EventSource = .claudeCode,
        tty: String? = "ttys003",
        cwd: String? = "/repo/backend",
        session: String? = "sess-1",
        title: String? = nil
    ) -> AgentEvent {
        AgentEvent(source: source, type: .done, tty: tty, cwd: cwd, session: session, title: title)
    }

    func testSessionKeyIsKeyedBySessionNotTTY() {
        // Same session, DIFFERENT ttys (a reused/changed tty) -> same toast.
        let a = event(tty: "ttys003", session: "sess-1")
        let b = event(tty: "ttys009", session: "sess-1")
        XCTAssertEqual(a.sessionKey, b.sessionKey)
    }

    func testSameTTYDifferentSessionsDoNotCollide() {
        // Same tty, DIFFERENT sessions (tty reused by a new session) -> distinct toasts.
        let a = event(tty: "ttys003", session: "sess-1")
        let b = event(tty: "ttys003", session: "sess-2")
        XCTAssertNotEqual(a.sessionKey, b.sessionKey)
    }

    func testSessionKeyIsNamespacedBySource() {
        let claude = event(source: .claudeCode, session: "shared-id")
        let codex = event(source: .codex, session: "shared-id")
        XCTAssertNotEqual(claude.sessionKey, codex.sessionKey)
        XCTAssertTrue(claude.sessionKey.hasPrefix("claude_code:"))
        XCTAssertTrue(codex.sessionKey.hasPrefix("codex:"))
    }

    func testSessionKeyFallsBackToTTYThenUnknown() {
        XCTAssertEqual(event(tty: "ttys003", session: nil).sessionKey, "claude_code:ttys003")
        XCTAssertEqual(event(tty: nil, session: nil).sessionKey, "claude_code:unknown")
        XCTAssertEqual(event(tty: "", session: "").sessionKey, "claude_code:unknown")
    }

    func testDisplayLabelPrefersTitleThenCwdBasenameThenAgentName() {
        XCTAssertEqual(event(title: "My Session").displayLabel, "My Session")
        XCTAssertEqual(event(cwd: "/repo/backend", title: nil).displayLabel, "backend")
        XCTAssertEqual(event(cwd: nil, title: nil).displayLabel, "Claude Code")
        XCTAssertEqual(event(source: .codex, cwd: nil, title: nil).displayLabel, "Codex")
        XCTAssertEqual(event(cwd: "/", title: nil).displayLabel, "Claude Code")
    }

    func testDismissEnvelopeRoundTripsSession() throws {
        let envelope = IPCEnvelope(command: .dismiss, session: "sess-1")
        let data = try JSONEncoder.clinotify.encode(envelope)
        let decoded = try JSONDecoder.clinotify.decode(IPCEnvelope.self, from: data)
        XCTAssertEqual(decoded.command, .dismiss)
        XCTAssertEqual(decoded.session, "sess-1")
    }
}
