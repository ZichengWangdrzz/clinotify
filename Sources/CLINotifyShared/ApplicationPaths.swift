import Foundation

public enum ApplicationPaths {
    /// Application Support subdirectory name. Channel-aware so the dev build keeps fully separate
    /// state (socket/lock/registry/preferences) from the installed production build.
    public static var appName: String { AppChannel.current.appSupportName }
    public static let socketFilename = "ipc.sock"
    public static let lockFilename = "helper.lock"
    public static let registryFilename = "sessions.json"
    public static let licenseFilename = "license.json"
    public static let preferencesFilename = "preferences.json"
    public static let sessionOverridesFilename = "session-overrides.json"

    public static var applicationSupportDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["CLINOTIFY_APP_SUPPORT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    public static var socketPath: String {
        applicationSupportDirectory.appendingPathComponent(socketFilename).path
    }

    public static var lockPath: String {
        applicationSupportDirectory.appendingPathComponent(lockFilename).path
    }

    public static var registryURL: URL {
        applicationSupportDirectory.appendingPathComponent(registryFilename)
    }

    public static var licenseURL: URL {
        applicationSupportDirectory.appendingPathComponent(licenseFilename)
    }

    public static var preferencesURL: URL {
        applicationSupportDirectory.appendingPathComponent(preferencesFilename)
    }

    public static var sessionOverridesURL: URL {
        applicationSupportDirectory.appendingPathComponent(sessionOverridesFilename)
    }

    /// The NSUserDefaults-backed preferences plist macOS writes for a channel's app
    /// (`~/Library/Preferences/<bundleid>.plist`). The daemon's SettingsStore uses `UserDefaults.standard`,
    /// so a full uninstall (`--purge`) must delete this too — purging the Application Support JSON alone
    /// leaves it behind (screen/sound-name keys would survive a reinstall).
    public static func preferencesPlistURL(
        for channel: AppChannel,
        home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> URL {
        home.appendingPathComponent("Library/Preferences/\(channel.bundleIdentifier).plist")
    }

    public static func ensureApplicationSupportDirectory() throws {
        try FileManager.default.createDirectory(
            at: applicationSupportDirectory,
            withIntermediateDirectories: true
        )
    }
}
