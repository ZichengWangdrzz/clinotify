import Foundation
import XCTest
@testable import CLINotifyShared

final class ApplicationPathsTests: XCTestCase {
    /// `uninstall --purge` deletes this plist, so the path must be channel-scoped and home-injectable
    /// (the daemon's SettingsStore persists to `~/Library/Preferences/<bundleid>.plist`).
    func testPreferencesPlistURLIsChannelScopedUnderHome() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        XCTAssertEqual(
            ApplicationPaths.preferencesPlistURL(for: .production, home: home).path,
            "/Users/test/Library/Preferences/app.clinotify.helper.plist"
        )
        XCTAssertEqual(
            ApplicationPaths.preferencesPlistURL(for: .dev, home: home).path,
            "/Users/test/Library/Preferences/app.clinotify.helper.dev.plist"
        )
    }
}
