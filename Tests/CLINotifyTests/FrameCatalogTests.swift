import Foundation
import XCTest
@testable import CLINotifyShared

final class FrameCatalogTests: XCTestCase {
    func testDefaultFrameIsPanel() {
        XCTAssertEqual(NotificationPreferences.defaultValue.claudeCodeFrameSkin, .panel)
        XCTAssertEqual(FrameCatalog.defaultClaudeCodeFrame(ownedFrameSkinIDs: []), .panel)
    }

    func testBothEntriesAreFree() {
        for entry in FrameCatalog.claudeCodeEntries {
            XCTAssertEqual(entry.access, .free, "\(entry.id.rawValue) should be free")
        }
        XCTAssertTrue(FrameCatalog.isClaudeCodeFrameAvailable(.panel, ownedFrameSkinIDs: []))
        XCTAssertTrue(FrameCatalog.isClaudeCodeFrameAvailable(.none, ownedFrameSkinIDs: []))
    }

    func testAvailableFramesIncludeFreeEntries() {
        let available = FrameCatalog.availableClaudeCodeFrames(ownedFrameSkinIDs: [])
        XCTAssertTrue(available.contains { $0.id == .panel })
        XCTAssertTrue(available.contains { $0.id == .none })
    }

    func testSelectedSkinReturnsPreference() {
        var preferences = NotificationPreferences()
        XCTAssertTrue(preferences.selectClaudeCodeFrameSkin(.none))
        XCTAssertEqual(
            FrameCatalog.selectedSkin(for: .claudeCode, preferences: preferences),
            .none
        )
        XCTAssertTrue(preferences.selectClaudeCodeFrameSkin(.panel))
        XCTAssertEqual(
            FrameCatalog.selectedSkin(for: .claudeCode, preferences: preferences),
            .panel
        )
    }

    func testNoneStyleIsTransparentAndPanelStyleIsVisible() {
        XCTAssertEqual(FrameSkin.none.style.fillColor.a, 0)
        XCTAssertEqual(FrameSkin.none.style.strokeColor.a, 0)
        XCTAssertGreaterThan(FrameSkin.panel.style.fillColor.a, 0)
        XCTAssertGreaterThan(FrameSkin.panel.style.cornerRadius, 0)
        XCTAssertTrue(FrameSkin.panel.style.hasShadow)
    }

    func testSelectFrameSkinRoundTripsThroughCodable() throws {
        var preferences = NotificationPreferences()
        XCTAssertTrue(preferences.selectClaudeCodeFrameSkin(.none))
        let data = try JSONEncoder.clinotify.encode(preferences)
        let decoded = try JSONDecoder.clinotify.decode(NotificationPreferences.self, from: data)
        XCTAssertEqual(decoded.claudeCodeFrameSkin, .none)
    }

    func testOldPreferencesWithoutFrameKeysDecodeToPanel() throws {
        // A prefs.json written before the frame axis existed: no claudeCodeFrameSkin / ownedFrameSkinIDs.
        let json = Data(#"""
        {
          "globalEnabled": true,
          "animationEnabled": true,
          "soundEnabled": true,
          "overlayScale": 1.0,
          "claudeCodeAnimation": "right-hand-wave",
          "claudeCodeBubbleSkin": "windows-xp",
          "ownedAnimationIDs": [],
          "ownedBubbleSkinIDs": []
        }
        """#.utf8)
        let decoded = try JSONDecoder.clinotify.decode(NotificationPreferences.self, from: json)
        XCTAssertEqual(decoded.claudeCodeFrameSkin, .panel)
        XCTAssertEqual(decoded.ownedFrameSkinIDs, [])
    }
}
