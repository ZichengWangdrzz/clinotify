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

    func testInstallWiresInteractiveSelectionToastLifecycle() throws {
        // Interactive selection prompts (AskUserQuestion / ExitPlanMode): showing one does NOT fire
        // Notification, and answering one fires PostToolUse (not UserPromptSubmit). So install must add
        // a PreToolUse "show" + a PostToolUse "dismiss", both scoped to those tools via the matcher.
        let home = temporaryHome()
        let settingsURL = home.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let installer = Installer(homeDirectory: home, cliURLProvider: { nil })
        try installer.installClaudeHooks()
        try installer.installClaudeHooks() // re-install: must stay idempotent (no duplicate entries)

        let hooks = try XCTUnwrap(loadJSON(settingsURL)["hooks"] as? [String: Any])

        // PreToolUse shows the toast the instant the choice appears, scoped to the selection tools.
        let preToolUse = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(
            commands(in: preToolUse).filter { $0 == "clinotify event --source claude_code --type attention" }.count,
            1
        )
        XCTAssertEqual(
            matcher(forCommand: "clinotify event --source claude_code --type attention", in: preToolUse),
            "AskUserQuestion|ExitPlanMode"
        )

        // PostToolUse dismisses it the instant the user answers.
        let postToolUse = try XCTUnwrap(hooks["PostToolUse"] as? [[String: Any]])
        XCTAssertEqual(commands(in: postToolUse).filter { $0 == "clinotify dismiss" }.count, 1)
        XCTAssertEqual(
            matcher(forCommand: "clinotify dismiss", in: postToolUse),
            "AskUserQuestion|ExitPlanMode"
        )

        // The plain Notification hook keeps the empty matcher (it fires for permission/idle prompts).
        let notification = try XCTUnwrap(hooks["Notification"] as? [[String: Any]])
        XCTAssertEqual(
            matcher(forCommand: "clinotify event --source claude_code --type attention", in: notification),
            ""
        )

        try installer.uninstallClaudeHooks()
        let remaining = try XCTUnwrap(loadJSON(settingsURL)["hooks"] as? [String: Any])
        XCTAssertNil(remaining["PreToolUse"] as? [[String: Any]])
        XCTAssertNil(remaining["PostToolUse"] as? [[String: Any]])
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
        // Uninstall consumes AND removes the backup — no orphaned *.clinotify.bak left behind.
        XCTAssertFalse(FileManager.default.fileExists(atPath: configURL.appendingPathExtension("clinotify.bak").path))
    }

    func testClaudeHooksUninstallRemovesOrphanedBackup() throws {
        let home = temporaryHome()
        let settingsURL = home.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Pre-existing settings so install() takes a backup.
        try #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo keep"}]}]}}"#
            .write(to: settingsURL, atomically: true, encoding: .utf8)

        let installer = Installer(homeDirectory: home, cliURLProvider: { nil })
        try installer.installClaudeHooks()
        let backupPath = settingsURL.appendingPathExtension("clinotify.bak").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupPath), "install should back up the prior settings")

        try installer.uninstallClaudeHooks()
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupPath), "uninstall should clear the orphaned backup")
        // Surgical removal preserved the user's own hook.
        let remaining = try loadJSON(settingsURL)
        let hooks = try XCTUnwrap(remaining["hooks"] as? [String: Any])
        XCTAssertEqual(commands(in: hooks["Stop"] as? [[String: Any]] ?? []), ["echo keep"])
    }

    func testCLISymlinkUninstallRestoresOriginalAndRemovesBackup() throws {
        let home = temporaryHome()
        let fileManager = FileManager.default
        let binDir = home.appendingPathComponent(".local/bin")
        try fileManager.createDirectory(at: binDir, withIntermediateDirectories: true)

        // A pre-existing `clinotify` the user already had, pointing at some other tool.
        let otherTool = home.appendingPathComponent("other-clinotify")
        try "#!/bin/sh\n".write(to: otherTool, atomically: true, encoding: .utf8)
        let linkURL = binDir.appendingPathComponent("clinotify")
        try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: otherTool)

        // Our bundled CLI that install() will point the symlink at.
        let ourCLI = home.appendingPathComponent("ours/clinotify")
        try fileManager.createDirectory(at: ourCLI.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: ourCLI, atomically: true, encoding: .utf8)

        let installer = Installer(homeDirectory: home, cliURLProvider: { ourCLI })
        try installer.install()
        XCTAssertEqual(try fileManager.destinationOfSymbolicLink(atPath: linkURL.path), ourCLI.path)
        let backupPath = linkURL.appendingPathExtension("clinotify.bak").path
        XCTAssertTrue(fileManager.fileExists(atPath: backupPath), "install should back up the prior symlink")

        try installer.uninstall()
        // The user's original symlink is restored, and the backup is gone.
        XCTAssertEqual(try fileManager.destinationOfSymbolicLink(atPath: linkURL.path), otherTool.path)
        XCTAssertFalse(fileManager.fileExists(atPath: backupPath))
    }

    private func commands(in entries: [[String: Any]]) -> [String] {
        entries.flatMap { entry in
            (entry["hooks"] as? [[String: Any]] ?? []).compactMap { hook in
                hook["command"] as? String
            }
        }
    }

    /// The `matcher` of the hook-group entry that contains the given command (nil if not present).
    private func matcher(forCommand command: String, in entries: [[String: Any]]) -> String? {
        for entry in entries {
            let cmds = (entry["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
            if cmds.contains(command) {
                return entry["matcher"] as? String
            }
        }
        return nil
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
