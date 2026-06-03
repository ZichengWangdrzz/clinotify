import Foundation

/// A launchd per-user agent that keeps the CLINotify helper running. With `RunAtLoad` + `KeepAlive`
/// the daemon starts at login and is relaunched whenever it exits, so the user never lands in the
/// "no daemon → sound but no toast" state (events fall back to a toast-less CLI sound when the daemon
/// is unreachable). The agent is channel-aware: its label is the channel's bundle id and it pins
/// `CLINOTIFY_CHANNEL`, so a dev agent and a production agent coexist without collision.
///
/// This type is pure (no launchctl / filesystem side effects) so the plist contents and paths are
/// unit-testable; the CLI does the actual write + `launchctl bootstrap`.
public enum LaunchAgent {
    /// launchd label == the channel's bundle id (`app.clinotify.helper` / `app.clinotify.helper.dev`).
    public static func label(for channel: AppChannel) -> String { channel.bundleIdentifier }

    /// Path of the per-user LaunchAgents plist for this channel.
    public static func plistURL(
        for channel: AppChannel,
        home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> URL {
        home.appendingPathComponent("Library/LaunchAgents/\(label(for: channel)).plist")
    }

    /// The plist XML. `daemonExecutablePath` is the `CLINotifyApp` binary inside the `.app` bundle.
    public static func plistXML(channel: AppChannel, daemonExecutablePath: String) -> String {
        let label = self.label(for: channel)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(xmlEscape(label))</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(xmlEscape(daemonExecutablePath))</string>
            </array>
            <key>EnvironmentVariables</key>
            <dict>
                <key>CLINOTIFY_CHANNEL</key>
                <string>\(channel.rawValue)</string>
            </dict>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>ProcessType</key>
            <string>Interactive</string>
        </dict>
        </plist>
        """
    }

    /// Minimal XML escaping for the few characters that are illegal in element text. Paths come from
    /// our own bundle resolution, but escape defensively so a `&`/`<`/`>` in a path can't break the plist.
    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
