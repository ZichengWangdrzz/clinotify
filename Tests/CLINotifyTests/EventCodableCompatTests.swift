import Foundation
import XCTest
@testable import CLINotifyShared

final class EventCodableCompatTests: XCTestCase {
    func testOldAgentEventDecodesWithoutPID() throws {
        let json = Data(#"""
        {"source":"claude_code","type":"done","tty":"ttys003","cwd":"/repo","session":"S","title":"T"}
        """#.utf8)
        let event = try JSONDecoder.clinotify.decode(AgentEvent.self, from: json)
        XCTAssertEqual(event.tty, "ttys003")
        XCTAssertNil(event.senderPID)
        XCTAssertNil(event.senderPPID)
    }

    func testAgentEventPIDRoundTrips() throws {
        let event = AgentEvent(
            source: .claudeCode,
            type: .attention,
            tty: "ttys003",
            cwd: "/repo",
            session: "S",
            title: "T",
            senderPID: 4242,
            senderPPID: 4200
        )
        let data = try JSONEncoder.clinotify.encode(event)
        let decoded = try JSONDecoder.clinotify.decode(AgentEvent.self, from: data)
        XCTAssertEqual(decoded, event)
        XCTAssertEqual(decoded.senderPID, 4242)
    }

    func testOldSessionRegistrationArrayDecodesWithoutNewFields() throws {
        let json = Data(#"""
        [{"tty":"ttys003","name":"Backend","cwd":"/repo","source":"codex","updatedAt":"2023-11-14T22:13:20Z"}]
        """#.utf8)
        let sessions = try JSONDecoder.clinotify.decode([SessionRegistration].self, from: json)
        XCTAssertEqual(sessions.first?.name, "Backend")
        XCTAssertNil(sessions.first?.pid)
        XCTAssertNil(sessions.first?.terminalBundleID)
    }

    func testSessionRegistrationNewFieldsRoundTripThroughRegistry() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("clinotify-reg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("sessions.json")

        let registration = SessionRegistration(
            tty: "ttys007",
            name: "Session",
            cwd: "/repo",
            source: .claudeCode,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            pid: 1234,
            ppid: 1000,
            terminalBundleID: "com.googlecode.iterm2"
        )
        let registry = SessionRegistry(url: url)
        try registry.register(registration)

        let reloaded = SessionRegistry(url: url)
        XCTAssertEqual(reloaded.registration(for: "ttys007"), registration)
        XCTAssertEqual(reloaded.registration(for: "ttys007")?.pid, 1234)
        XCTAssertEqual(reloaded.registration(for: "ttys007")?.terminalBundleID, "com.googlecode.iterm2")
    }

    func testIPCEnvelopeOverrideRoundTrips() throws {
        let envelope = IPCEnvelope(
            command: .setOverride,
            tty: "ttys003",
            override: SessionPreferenceOverride(soundMuted: true)
        )
        let data = try JSONEncoder.clinotify.encode(envelope)
        let decoded = try JSONDecoder.clinotify.decode(IPCEnvelope.self, from: data)
        XCTAssertEqual(decoded.command, .setOverride)
        XCTAssertEqual(decoded.override?.soundMuted, true)
    }
}
