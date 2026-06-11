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

    /// CLI name for this channel (`clinotify` or `clinotify-dev`). Used only to MATCH the legacy v0.1.0
    /// hook lines (which referenced the bare name) so an upgrade migrates them to the absolute path.
    private var cli: String { channel.cliName }
    /// Absolute path to the installed CLI symlink (`~/.local/bin/<cli>`). Hook subprocesses spawned by
    /// Claude Code / Codex do NOT inherit the user's interactive shell PATH — especially when the agent
    /// was launched from a GUI/IDE (VS Code, JetBrains), where `~/.local/bin` is essentially never on
    /// PATH. A bare `clinotify` would be command-not-found and the hook would silently no-op. Writing the
    /// absolute path makes the hook fire regardless of PATH.
    private var cliPath: String { home(".local/bin/\(channel.cliName)").path }
    /// Shell-quoted absolute path. Claude runs hook commands via a shell, so quote it in case the home
    /// directory contains spaces.
    private var quotedCLIPath: String { "\"\(cliPath)\"" }
    private var claudeDoneCommand: String { "\(quotedCLIPath) event --source claude_code --type done" }
    private var claudeAttentionCommand: String { "\(quotedCLIPath) event --source claude_code --type attention" }
    private var claudeDismissCommand: String { "\(quotedCLIPath) dismiss" }
    private var codexNotifyLine: String { "notify = [\"\(cliPath)\", \"codex-event\"]" }

    // Legacy v0.1.0 bare-name forms. Stripped on install (migrated to the absolute path above) and on
    // uninstall, so upgrading from v0.1.0 never leaves a duplicate or an orphaned bare hook line.
    private var legacyClaudeDoneCommand: String { "\(cli) event --source claude_code --type done" }
    private var legacyClaudeAttentionCommand: String { "\(cli) event --source claude_code --type attention" }
    private var legacyClaudeDismissCommand: String { "\(cli) dismiss" }
    private var legacyCodexNotifyLine: String { "notify = [\"\(cli)\", \"codex-event\"]" }

    /// Interactive-selection tools: ones that present a choice and then block waiting for the user.
    /// `AskUserQuestion` (a question with options) and `ExitPlanMode` (plan approval) are the two.
    /// They are special because (1) showing one does NOT fire the `Notification` hook — only the 60s
    /// `idle_prompt` does (anthropics/claude-code#13830) — and (2) answering one fires `PostToolUse`,
    /// NOT `UserPromptSubmit`. So without a PreToolUse/PostToolUse pair the toast neither appears
    /// promptly at the choice nor slides out when the user answers. The string is a hook matcher,
    /// matched against the exact tool name; `|` means OR (case-sensitive).
    private let claudeSelectionMatcher = "AskUserQuestion|ExitPlanMode"

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
        // For each event: strip any legacy v0.1.0 bare-name line first (migration), then merge the
        // current absolute-path command. Stripping-then-merging keeps install idempotent across the
        // command-format change so an upgrade never leaves a duplicate hook.
        hooks["Stop"] = mergedClaudeHookArray(
            existing: removeClaudeCommand(from: hooks["Stop"] as? [[String: Any]] ?? [], command: legacyClaudeDoneCommand),
            command: claudeDoneCommand
        )
        hooks["Notification"] = mergedClaudeHookArray(
            existing: removeClaudeCommand(from: hooks["Notification"] as? [[String: Any]] ?? [], command: legacyClaudeAttentionCommand),
            command: claudeAttentionCommand
        )
        // Auto-dismiss the toast the moment the user submits a prompt in that session, and clean up
        // when the session ends. Both pass the session_id on stdin, which `clinotify dismiss` reads.
        hooks["UserPromptSubmit"] = mergedClaudeHookArray(
            existing: removeClaudeCommand(from: hooks["UserPromptSubmit"] as? [[String: Any]] ?? [], command: legacyClaudeDismissCommand),
            command: claudeDismissCommand
        )
        hooks["SessionEnd"] = mergedClaudeHookArray(
            existing: removeClaudeCommand(from: hooks["SessionEnd"] as? [[String: Any]] ?? [], command: legacyClaudeDismissCommand),
            command: claudeDismissCommand
        )
        // Interactive selection prompts (AskUserQuestion / ExitPlanMode) don't fire Notification when
        // shown, and answering one is a PostToolUse rather than a UserPromptSubmit. So show the toast
        // on PreToolUse (the instant the choice appears) and dismiss it on PostToolUse (the instant
        // the user answers) — both scoped to those tools via the matcher.
        hooks["PreToolUse"] = mergedClaudeHookArray(
            existing: removeClaudeCommand(from: hooks["PreToolUse"] as? [[String: Any]] ?? [], command: legacyClaudeAttentionCommand),
            command: claudeAttentionCommand,
            matcher: claudeSelectionMatcher
        )
        hooks["PostToolUse"] = mergedClaudeHookArray(
            existing: removeClaudeCommand(from: hooks["PostToolUse"] as? [[String: Any]] ?? [], command: legacyClaudeDismissCommand),
            command: claudeDismissCommand,
            matcher: claudeSelectionMatcher
        )
        root["hooks"] = hooks
        try writeJSONObject(root, to: url)
    }

    public func uninstallClaudeHooks() throws {
        let url = home(".claude/settings.json")
        guard var root = try loadJSONObject(url),
              var hooks = root["hooks"] as? [String: Any] else { return }
        // Remove BOTH the current absolute-path command and the legacy v0.1.0 bare-name form, so an
        // uninstall after upgrading from v0.1.0 leaves nothing behind.
        setOrRemove(key: "Stop", in: &hooks,
            value: removeClaudeCommands(from: hooks["Stop"] as? [[String: Any]] ?? [], claudeDoneCommand, legacyClaudeDoneCommand))
        setOrRemove(key: "Notification", in: &hooks,
            value: removeClaudeCommands(from: hooks["Notification"] as? [[String: Any]] ?? [], claudeAttentionCommand, legacyClaudeAttentionCommand))
        setOrRemove(key: "UserPromptSubmit", in: &hooks,
            value: removeClaudeCommands(from: hooks["UserPromptSubmit"] as? [[String: Any]] ?? [], claudeDismissCommand, legacyClaudeDismissCommand))
        setOrRemove(key: "SessionEnd", in: &hooks,
            value: removeClaudeCommands(from: hooks["SessionEnd"] as? [[String: Any]] ?? [], claudeDismissCommand, legacyClaudeDismissCommand))
        setOrRemove(key: "PreToolUse", in: &hooks,
            value: removeClaudeCommands(from: hooks["PreToolUse"] as? [[String: Any]] ?? [], claudeAttentionCommand, legacyClaudeAttentionCommand))
        setOrRemove(key: "PostToolUse", in: &hooks,
            value: removeClaudeCommands(from: hooks["PostToolUse"] as? [[String: Any]] ?? [], claudeDismissCommand, legacyClaudeDismissCommand))
        root["hooks"] = hooks
        try writeJSONObject(root, to: url)
        // Surgical removal preserves hooks the user added after install, so we never restore the full
        // backup — just clear the orphan so uninstall leaves no `*.clinotify.bak` behind.
        try? fileManager.removeItem(at: url.appendingPathExtension("clinotify.bak"))
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
            // Backup consumed: remove it so uninstall leaves no orphaned `*.clinotify.bak`.
            try? fileManager.removeItem(at: backupURL)
            return
        }

        guard let existing = try? String(contentsOf: url, encoding: .utf8) else { return }
        let output = existing
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter {
                let trimmed = $0.trimmingCharacters(in: .whitespaces)
                return trimmed != codexNotifyLine && trimmed != legacyCodexNotifyLine
            }
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
        let backupURL = linkURL.appendingPathExtension("clinotify.bak")
        guard fileManager.fileExists(atPath: linkURL.path),
              let destination = try? fileManager.destinationOfSymbolicLink(atPath: linkURL.path),
              destination == cliURLProvider()?.path else {
            return
        }
        try fileManager.removeItem(at: linkURL)
        // If install() backed up a pre-existing symlink, restore the user's original, then clear the
        // backup so no orphaned `*.clinotify.bak` is left behind.
        try? fileManager.copyItem(at: backupURL, to: linkURL)
        try? fileManager.removeItem(at: backupURL)
    }

    private func mergedClaudeHookArray(existing: [[String: Any]], command: String, matcher: String = "") -> [[String: Any]] {
        if containsClaudeCommand(existing, command: command) {
            return existing
        }
        var result = existing
        result.append([
            "matcher": matcher,
            "hooks": [
                [
                    "type": "command",
                    "command": command
                ]
            ]
        ])
        return result
    }

    /// Strip every listed command from the event array (used to remove the current command AND its
    /// legacy bare-name form in one pass).
    private func removeClaudeCommands(from existing: [[String: Any]], _ commands: String...) -> [[String: Any]] {
        commands.reduce(existing) { removeClaudeCommand(from: $0, command: $1) }
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
        // Skip the write when the normalized content is unchanged (idempotent re-install), so a no-op
        // never rewrites the user's settings.json or churns its mtime. .sortedKeys is kept because it
        // makes the output deterministic — JSONSerialization round-trips through an unordered dictionary,
        // so the user's original key order can't be preserved here regardless; sorting at least keeps
        // re-installs from producing spurious diffs.
        if let existing = try? Data(contentsOf: url),
           let existingObject = try? JSONSerialization.jsonObject(with: existing),
           let normalizedExisting = try? JSONSerialization.data(withJSONObject: existingObject, options: [.prettyPrinted, .sortedKeys]),
           normalizedExisting == data {
            return
        }
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
