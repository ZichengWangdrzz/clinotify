import Foundation
import XCTest
@testable import CLINotifyShared

final class SessionRegistryTests: XCTestCase {
    func testRegisterPersistReloadAndUnregister() throws {
        let directory = temporaryDirectory()
        let url = directory.appendingPathComponent("sessions.json")
        let registry = SessionRegistry(url: url)
        let registration = SessionRegistration(
            tty: "ttys003",
            name: "Backend refactor",
            cwd: "/repo",
            source: .codex,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        try registry.register(registration)
        XCTAssertEqual(registry.registration(for: "ttys003")?.name, "Backend refactor")

        let reloaded = SessionRegistry(url: url)
        XCTAssertEqual(reloaded.registration(for: "ttys003"), registration)

        try reloaded.unregister(tty: "ttys003")
        XCTAssertNil(reloaded.registration(for: "ttys003"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    private func temporaryDirectory() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("clinotify-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
