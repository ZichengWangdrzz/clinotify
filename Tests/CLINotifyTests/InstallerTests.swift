import Foundation
import XCTest
@testable import CLINotifyShared

final class InstallerTests: XCTestCase {
    func testClaudeHookInstallMergesAndUninstallRemovesOnlyClinotifyHooks() throws {
        let home = temporaryHome()
        let settingsURL = home.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        {
          "hooks": {
            "Stop": [
              {
                "matcher": "existing",
                "hooks": [
                  { "type": "command", "command": "echo keep" }
                ]
              }
            ]
          }
        }
        """.write(to: settingsURL, atomically: true, encoding: .utf8)

        let installer = Installer(homeDirectory: home, cliURLProvider: { nil })
        try installer.installClaudeHooks()
        let installed = try loadJSON(settingsURL)
        let hooks = try XCTUnwrap(installed["hooks"] as? [String: Any])
        let stop = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        let notification = try XCTUnwrap(hooks["Notification"] as? [[String: Any]])

        XCTAssertTrue(commands(in: stop).contains("echo keep"))
        XCTAssertTrue(commands(in: stop).contains("clinotify event --source claude_code --type done"))
        XCTAssertTrue(commands(in: notification).contains("clinotify event --source claude_code --type attention"))

        // The toast lifecycle hooks (ADR-0002): auto-dismiss on the user's next prompt, and clean up
        // when the session ends. Both invoke `clinotify dismiss` (which reads session_id from stdin).
        let userPromptSubmit = try XCTUnwrap(hooks["UserPromptSubmit"] as? [[String: Any]])
        let sessionEnd = try XCTUnwrap(hooks["SessionEnd"] as? [[String: Any]])
        XCTAssertTrue(commands(in: userPromptSubmit).contains("clinotify dismiss"))
        XCTAssertTrue(commands(in: sessionEnd).contains("clinotify dismiss"))

        try installer.uninstallClaudeHooks()
        let uninstalled = try loadJSON(settingsURL)
        let remainingHooks = try XCTUnwrap(uninstalled["hooks"] as? [String: Any])
        let remainingStop = try XCTUnwrap(remainingHooks["Stop"] as? [[String: Any]])
        XCTAssertEqual(commands(in: remainingStop), ["echo keep"])
        XCTAssertNil(remainingHooks["Notification"] as? [[String: Any]])
        XCTAssertNil(remainingHooks["UserPromptSubmit"] as? [[String: Any]])
        XCTAssertNil(remainingHooks["SessionEnd"] as? [[String: Any]])
    }

    func testDevChannelHooksCoexistWithProductionAndUninstallIsScoped() throws {
        let home = temporaryHome()
        let settingsURL = home.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let prod = Installer(channel: .production, homeDirectory: home, cliURLProvider: { nil })
        let dev = Installer(channel: .dev, homeDirectory: home, cliURLProvider: { nil })
        try prod.installClaudeHooks()
        try dev.installClaudeHooks()

        var hooks = try XCTUnwrap(loadJSON(settingsURL)["hooks"] as? [String: Any])
        var stop = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        // Both channels' hook lines live side-by-side; the dev one targets the clinotify-dev CLI.
        XCTAssertTrue(commands(in: stop).contains("clinotify event --source claude_code --type done"))
        XCTAssertTrue(commands(in: stop).contains("clinotify-dev event --source claude_code --type done"))

        // Uninstalling dev must leave the production hooks intact.
        try dev.uninstallClaudeHooks()
        hooks = try XCTUnwrap(loadJSON(settingsURL)["hooks"] as? [String: Any])
        stop = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        XCTAssertTrue(commands(in: stop).contains("clinotify event --source claude_code --type done"))
        XCTAssertFalse(commands(in: stop).contains("clinotify-dev event --source claude_code --type done"))
    }

    func testCodexNotifyInstallBacksUpAndUninstallRestores() throws {
        let home = temporaryHome()
        let configURL = home.appendingPathComponent(".codex/config.toml")
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let original = """
        model = "gpt-5"
        notify = ["terminal-notifier", "-message", "done"]
        """
        try original.write(to: configURL, atomically: true, encoding: .utf8)

        let installer = Installer(homeDirectory: home, cliURLProvider: { nil })
        try installer.installCodexNotify()

        let installed = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(installed.contains(#"notify = ["clinotify", "codex-event"]"#))
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.appendingPathExtension("clinotify.bak").path))

        try installer.uninstallCodexNotify()
        let restored = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertEqual(restored, original)
    }

    private func commands(in entries: [[String: Any]]) -> [String] {
        entries.flatMap { entry in
            (entry["hooks"] as? [[String: Any]] ?? []).compactMap { hook in
                hook["command"] as? String
            }
        }
    }

    private func loadJSON(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func temporaryHome() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("clinotify-home-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
