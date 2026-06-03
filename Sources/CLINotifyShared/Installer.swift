import Foundation

public final class Installer {
    private let fileManager: FileManager
    private let homeDirectory: URL
    private let cliURLProvider: () -> URL?
    /// The channel being installed. Drives the CLI symlink name + hook command lines so a dev install
    /// coexists with a production install instead of clobbering it.
    private let channel: AppChannel

    public init(
        channel: AppChannel = .current,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        fileManager: FileManager = .default,
        cliURLProvider: @escaping () -> URL? = Installer.defaultBundledCLIURL
    ) {
        self.channel = channel
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
        self.cliURLProvider = cliURLProvider
    }

    /// CLI name for this channel (`clinotify` or `clinotify-dev`).
    private var cli: String { channel.cliName }
    private var claudeDoneCommand: String { "\(cli) event --source claude_code --type done" }
    private var claudeAttentionCommand: String { "\(cli) event --source claude_code --type attention" }
    private var claudeDismissCommand: String { "\(cli) dismiss" }
    private var codexNotifyLine: String { "notify = [\"\(cli)\", \"codex-event\"]" }

    public func install() throws {
        try installCLISymlink()
        try installClaudeHooks()
        try installCodexNotify()
    }

    public func uninstall() throws {
        try uninstallCLISymlink()
        try uninstallClaudeHooks()
        try uninstallCodexNotify()
    }

    public func installClaudeHooks() throws {
        let url = home(".claude/settings.json")
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        backup(url)

        var root = try loadJSONObject(url) ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        hooks["Stop"] = mergedClaudeHookArray(
            existing: hooks["Stop"] as? [[String: Any]] ?? [],
            command: claudeDoneCommand
        )
        hooks["Notification"] = mergedClaudeHookArray(
            existing: hooks["Notification"] as? [[String: Any]] ?? [],
            command: claudeAttentionCommand
        )
        // Auto-dismiss the toast the moment the user submits a prompt in that session, and clean up
        // when the session ends. Both pass the session_id on stdin, which `clinotify dismiss` reads.
        hooks["UserPromptSubmit"] = mergedClaudeHookArray(
            existing: hooks["UserPromptSubmit"] as? [[String: Any]] ?? [],
            command: claudeDismissCommand
        )
        hooks["SessionEnd"] = mergedClaudeHookArray(
            existing: hooks["SessionEnd"] as? [[String: Any]] ?? [],
            command: claudeDismissCommand
        )
        root["hooks"] = hooks
        try writeJSONObject(root, to: url)
    }

    public func uninstallClaudeHooks() throws {
        let url = home(".claude/settings.json")
        guard var root = try loadJSONObject(url),
              var hooks = root["hooks"] as? [String: Any] else { return }
        setOrRemove(
            key: "Stop",
            in: &hooks,
            value: removeClaudeCommand(
            from: hooks["Stop"] as? [[String: Any]] ?? [],
            command: claudeDoneCommand
            )
        )
        setOrRemove(
            key: "Notification",
            in: &hooks,
            value: removeClaudeCommand(
            from: hooks["Notification"] as? [[String: Any]] ?? [],
            command: claudeAttentionCommand
            )
        )
        setOrRemove(
            key: "UserPromptSubmit",
            in: &hooks,
            value: removeClaudeCommand(
            from: hooks["UserPromptSubmit"] as? [[String: Any]] ?? [],
            command: claudeDismissCommand
            )
        )
        setOrRemove(
            key: "SessionEnd",
            in: &hooks,
            value: removeClaudeCommand(
            from: hooks["SessionEnd"] as? [[String: Any]] ?? [],
            command: claudeDismissCommand
            )
        )
        root["hooks"] = hooks
        try writeJSONObject(root, to: url)
    }

    public func installCodexNotify() throws {
        let url = home(".codex/config.toml")
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        backup(url)
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let line = codexNotifyLine
        let lines = existing.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var replaced = false
        let rewritten = lines.map { sourceLine in
            if sourceLine.trimmingCharacters(in: .whitespaces).hasPrefix("notify =") {
                replaced = true
                return line
            }
            return sourceLine
        }
        let output = replaced ? rewritten.joined(separator: "\n") : [existing.trimmingCharacters(in: .newlines), line]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        try output.appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    public func uninstallCodexNotify() throws {
        let url = home(".codex/config.toml")
        let backupURL = url.appendingPathExtension("clinotify.bak")
        if fileManager.fileExists(atPath: backupURL.path) {
            try? fileManager.removeItem(at: url)
            try fileManager.copyItem(at: backupURL, to: url)
            return
        }

        guard let existing = try? String(contentsOf: url, encoding: .utf8) else { return }
        let output = existing
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.trimmingCharacters(in: .whitespaces) != codexNotifyLine }
            .joined(separator: "\n")
        try output.write(to: url, atomically: true, encoding: .utf8)
    }

    private func installCLISymlink() throws {
        guard let cliURL = cliURLProvider() else { return }
        let binDirectory = home(".local/bin")
        try fileManager.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        let linkURL = binDirectory.appendingPathComponent(channel.cliName)
        if fileManager.fileExists(atPath: linkURL.path) {
            let destination = try? fileManager.destinationOfSymbolicLink(atPath: linkURL.path)
            if destination == cliURL.path {
                return
            }
            backup(linkURL)
            try? fileManager.removeItem(at: linkURL)
        }
        try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: cliURL)
    }

    private func uninstallCLISymlink() throws {
        let linkURL = home(".local/bin/\(channel.cliName)")
        guard fileManager.fileExists(atPath: linkURL.path),
              let destination = try? fileManager.destinationOfSymbolicLink(atPath: linkURL.path),
              destination == cliURLProvider()?.path else {
            return
        }
        try fileManager.removeItem(at: linkURL)
    }

    private func mergedClaudeHookArray(existing: [[String: Any]], command: String) -> [[String: Any]] {
        if containsClaudeCommand(existing, command: command) {
            return existing
        }
        var result = existing
        result.append([
            "matcher": "",
            "hooks": [
                [
                    "type": "command",
                    "command": command
                ]
            ]
        ])
        return result
    }

    private func removeClaudeCommand(from existing: [[String: Any]], command: String) -> [[String: Any]] {
        existing.compactMap { entry in
            var mutable = entry
            let hooks = (entry["hooks"] as? [[String: Any]] ?? []).filter { hook in
                hook["command"] as? String != command
            }
            mutable["hooks"] = hooks
            return hooks.isEmpty ? nil : mutable
        }
    }

    private func containsClaudeCommand(_ existing: [[String: Any]], command: String) -> Bool {
        existing.contains { entry in
            (entry["hooks"] as? [[String: Any]] ?? []).contains { hook in
                hook["command"] as? String == command
            }
        }
    }

    private func setOrRemove(key: String, in hooks: inout [String: Any], value: [[String: Any]]) {
        if value.isEmpty {
            hooks.removeValue(forKey: key)
        } else {
            hooks[key] = value
        }
    }

    private func loadJSONObject(_ url: URL) throws -> [String: Any]? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [:] }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private func backup(_ url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let backupURL = url.appendingPathExtension("clinotify.bak")
        guard !fileManager.fileExists(atPath: backupURL.path) else { return }
        try? fileManager.copyItem(at: url, to: backupURL)
    }

    private func home(_ path: String) -> URL {
        homeDirectory.appendingPathComponent(path)
    }

    public static func defaultBundledCLIURL() -> URL? {
        let bundleCandidate = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/clinotify")
        if FileManager.default.fileExists(atPath: bundleCandidate.path) {
            return bundleCandidate
        }
        guard let executableURL = Bundle.main.executableURL else { return nil }
        let siblingCandidate = executableURL.deletingLastPathComponent().appendingPathComponent("clinotify")
        return FileManager.default.fileExists(atPath: siblingCandidate.path) ? siblingCandidate : nil
    }

}
