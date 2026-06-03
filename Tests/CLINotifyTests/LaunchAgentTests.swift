import Foundation
import XCTest
@testable import CLINotifyShared

final class LaunchAgentTests: XCTestCase {
    func testLabelAndPlistPathAreChannelScoped() {
        XCTAssertEqual(LaunchAgent.label(for: .production), "app.clinotify.helper")
        XCTAssertEqual(LaunchAgent.label(for: .dev), "app.clinotify.helper.dev")

        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        XCTAssertEqual(
            LaunchAgent.plistURL(for: .production, home: home).path,
            "/Users/test/Library/LaunchAgents/app.clinotify.helper.plist"
        )
        XCTAssertEqual(
            LaunchAgent.plistURL(for: .dev, home: home).path,
            "/Users/test/Library/LaunchAgents/app.clinotify.helper.dev.plist"
        )
    }

    func testPlistXMLContainsProgramChannelAndKeepAlive() {
        let xml = LaunchAgent.plistXML(
            channel: .production,
            daemonExecutablePath: "/Applications/CLINotify.app/Contents/MacOS/CLINotifyApp"
        )
        XCTAssertTrue(xml.contains("<string>app.clinotify.helper</string>"))
        XCTAssertTrue(xml.contains("<string>/Applications/CLINotify.app/Contents/MacOS/CLINotifyApp</string>"))
        // Pins the channel so the launched daemon resolves the right identity.
        XCTAssertTrue(xml.contains("<key>CLINOTIFY_CHANNEL</key>"))
        XCTAssertTrue(xml.contains("<string>production</string>"))
        // Durability: starts at login AND relaunches if it exits.
        XCTAssertTrue(xml.contains("<key>RunAtLoad</key>"))
        XCTAssertTrue(xml.contains("<key>KeepAlive</key>"))
        // Well-formed enough to parse back as a plist with the expected top-level keys.
        let data = Data(xml.utf8)
        let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let dict = object as? [String: Any]
        XCTAssertEqual(dict?["Label"] as? String, "app.clinotify.helper")
        XCTAssertEqual(dict?["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(dict?["KeepAlive"] as? Bool, true)
        XCTAssertEqual((dict?["ProgramArguments"] as? [String])?.first, "/Applications/CLINotify.app/Contents/MacOS/CLINotifyApp")
    }

    func testPlistXMLPinsDevChannel() {
        let xml = LaunchAgent.plistXML(
            channel: .dev,
            daemonExecutablePath: "/x/CLINotify Dev.app/Contents/MacOS/CLINotifyApp"
        )
        XCTAssertTrue(xml.contains("<string>app.clinotify.helper.dev</string>"))
        XCTAssertTrue(xml.contains("<string>dev</string>"))
    }

    /// `disable` must boot the agent out of launchd AND delete the plist, so an uninstall can never
    /// leave a KeepAlive agent behind to resurrect the daemon. launchctl is stubbed so the test never
    /// touches the developer's real agent (the label is the fixed channel bundle id, not `home`-scoped).
    func testLaunchAgentControlDisableBootsOutAndRemovesPlist() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("clinotify-la-\(UUID().uuidString)", isDirectory: true)
        let plistURL = LaunchAgent.plistURL(for: .production, home: home)
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try LaunchAgent.plistXML(channel: .production, daemonExecutablePath: "/Applications/CLINotify.app/Contents/MacOS/CLINotifyApp")
            .write(to: plistURL, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))

        var calls: [[String]] = []
        let removed = LaunchAgentControl.disable(for: .production, home: home, launchctl: { args in
            calls.append(args)
            return true
        })

        XCTAssertTrue(removed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path))
        // bootout must run before the plist removal so KeepAlive stops first.
        XCTAssertEqual(calls.first?.first, "bootout")
        XCTAssertTrue(calls.first?.last?.hasSuffix("app.clinotify.helper") ?? false)
        XCTAssertTrue(calls.contains { $0.first == "unload" })
    }

    /// Disabling when autostart was never enabled (no plist) is a harmless no-op that still "succeeds".
    func testLaunchAgentControlDisableIsNoOpWhenNotInstalled() {
        let home = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("clinotify-la-\(UUID().uuidString)", isDirectory: true)
        let removed = LaunchAgentControl.disable(for: .production, home: home, launchctl: { _ in false })
        XCTAssertTrue(removed)
    }
}
