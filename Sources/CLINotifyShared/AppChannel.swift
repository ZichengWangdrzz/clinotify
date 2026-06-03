import Foundation

/// Which build "channel" this process belongs to. The `dev` channel is a fully separate identity —
/// app name, bundle id, CLI name, state directory, and hook lines — so a local development build can
/// run side-by-side with the installed production build with zero collision (separate socket, lock,
/// registry, preferences, and Claude/Codex hooks). This is what lets you test the downloaded product
/// as a real user while still iterating on your local code.
public enum AppChannel: String, Sendable {
    case production
    case dev

    /// The channel for the current process.
    public static var current: AppChannel {
        resolve(
            invokedName: (CommandLine.arguments.first as NSString?)?.lastPathComponent,
            environment: ProcessInfo.processInfo.environment
        )
    }

    /// Pure, testable resolver. Precedence:
    /// 1. `CLINOTIFY_CHANNEL` env var (`dev` or `production`/`prod`) — set by the dev app bundle's
    ///    Info.plist `LSEnvironment`, or exported manually for a raw dev daemon run.
    /// 2. An invoked binary name ending in `-dev` (e.g. `clinotify-dev`) — lets the dev CLI and the
    ///    dev hook commands select the channel with no env var.
    /// 3. Default: production.
    public static func resolve(invokedName: String?, environment: [String: String]) -> AppChannel {
        if let raw = environment["CLINOTIFY_CHANNEL"]?.lowercased(), !raw.isEmpty {
            if raw == "dev" { return .dev }
            if raw == "production" || raw == "prod" { return .production }
        }
        if let name = invokedName, name.hasSuffix("-dev") { return .dev }
        return .production
    }

    /// Directory name under Application Support (drives socket/lock/registry/preferences paths).
    public var appSupportName: String { self == .dev ? "CLINotify-Dev" : "CLINotify" }
    /// CLI binary/symlink name on PATH and inside hook command lines.
    public var cliName: String { self == .dev ? "clinotify-dev" : "clinotify" }
    /// macOS bundle identifier.
    public var bundleIdentifier: String { self == .dev ? "app.clinotify.helper.dev" : "app.clinotify.helper" }
    /// Human-facing app name (bundle name, menu-bar tooltip).
    public var displayName: String { self == .dev ? "CLINotify Dev" : "CLINotify" }
}
