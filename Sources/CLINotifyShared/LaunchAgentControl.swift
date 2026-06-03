import Foundation

/// Side-effecting controller for the per-user autostart `LaunchAgent`.
///
/// Kept separate from the pure `LaunchAgent` builder (which only produces plist contents + paths so
/// it stays unit-testable) — this type is where the `launchctl` / filesystem teardown lives. Both the
/// `clinotify` CLI (`autostart off`, `uninstall`) and the menu-bar app ("Uninstall Hooks") route
/// through `disable(for:)` so there is exactly ONE teardown sequence and uninstall can never leave a
/// launchd KeepAlive agent behind to resurrect a deleted daemon.
public enum LaunchAgentControl {
    /// Tear down the autostart LaunchAgent for `channel`: bootout from the GUI launchd domain, `unload`
    /// (older-API fallback), then delete the plist. Tolerant of "not loaded" / "not found" — running it
    /// when autostart was never enabled is a harmless no-op. Returns true once no plist remains.
    ///
    /// `launchctl` is injectable so tests can verify the teardown sequence + plist removal without
    /// invoking the real `/bin/launchctl` (which would otherwise bootout the developer's actual agent,
    /// since the launchd label is the fixed channel bundle id regardless of `home`).
    @discardableResult
    public static func disable(
        for channel: AppChannel,
        home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        launchctl: ([String]) -> Bool = LaunchAgentControl.runLaunchctl
    ) -> Bool {
        let label = LaunchAgent.label(for: channel)
        let plistURL = LaunchAgent.plistURL(for: channel, home: home)
        let domainTarget = "gui/\(getuid())/\(label)"
        // bootout (modern) first so KeepAlive stops; unload -w covers older launchd; then remove the file.
        _ = launchctl(["bootout", domainTarget])
        _ = launchctl(["unload", "-w", plistURL.path])
        try? FileManager.default.removeItem(at: plistURL)
        return !FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// Run `/bin/launchctl` with `args`; true on exit 0. launchctl is noisy on already-loaded /
    /// not-loaded states, so callers treat a nonzero exit as tolerable — the plist-absence check in
    /// `disable` is the real success signal.
    @discardableResult
    public static func runLaunchctl(_ args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
