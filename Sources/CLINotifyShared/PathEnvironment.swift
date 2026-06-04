import Foundation

/// Helpers for the one manual step `clinotify install` can't do for the user: making the installed CLI
/// symlink (`~/.local/bin/<cli>`) reachable on `PATH`. Install only creates the symlink — it never edits
/// a shell profile — so the CLI surfaces a hint when `~/.local/bin` isn't on PATH, and the menu-bar app
/// shows an informational note (a Finder-launched app gets a minimal PATH that can't see the user's
/// shell, so it must never warn *conditionally* or it would false-positive every time).
public enum PathEnvironment {
    /// Directory the install symlink lives in (`~/.local/bin`).
    public static func binDirectory(
        home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> URL {
        home.appendingPathComponent(".local/bin", isDirectory: true)
    }

    /// Whether `directory` is one of the colon-separated entries in `pathValue`.
    public static func isOnPath(_ directory: URL, pathValue: String) -> Bool {
        let target = directory.standardizedFileURL.path
        return pathValue
            .split(separator: ":", omittingEmptySubsequences: true)
            .map { URL(fileURLWithPath: String($0)).standardizedFileURL.path }
            .contains(target)
    }

    /// A user-facing hint to add `directory` to PATH, or `nil` if it's already there. `command` is the
    /// CLI name shown in the message; `shell` selects the profile file + syntax (defaults to `$SHELL`).
    public static func pathExportHint(
        for directory: URL,
        pathValue: String,
        command: String = "clinotify",
        shell: String? = nil
    ) -> String? {
        if isOnPath(directory, pathValue: pathValue) { return nil }
        let dir = directory.standardizedFileURL.path
        let resolved = (shell ?? ProcessInfo.processInfo.environment["SHELL"] ?? "").lowercased()
        let profile: String
        let line: String
        if resolved.contains("fish") {
            profile = "~/.config/fish/config.fish"
            line = "fish_add_path \(dir)"
        } else if resolved.contains("bash") {
            profile = "~/.bash_profile"
            line = "export PATH=\"\(dir):$PATH\""
        } else {
            profile = "~/.zshrc"
            line = "export PATH=\"\(dir):$PATH\""
        }
        return """
        Note: \(dir) is not on your PATH, so the `\(command)` command won't be found yet. Add it with:
          echo '\(line)' >> \(profile)
        then restart your terminal (or run that line in your current shell).
        """
    }
}
