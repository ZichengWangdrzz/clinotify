import Foundation
import XCTest
@testable import CLINotifyShared

final class NotificationPreferencesStoreTests: XCTestCase {
    func testDefaultsWhenFileIsMissing() {
        let store = NotificationPreferencesStore(url: temporaryFile())

        XCTAssertEqual(store.load(), .defaultValue)
        XCTAssertEqual(store.load().overlayScale, 1.0)
    }

    func testSaveAndReloadClaudeCodeAnimationSelection() throws {
        let url = temporaryFile()
        let store = NotificationPreferencesStore(url: url)
        let preferences = NotificationPreferences(
            globalEnabled: true,
            animationEnabled: true,
            soundEnabled: false,
            overlayScale: 1.25,
            claudeCodeAnimation: .squintLegWave,
            claudeCodeBubbleSkin: .windowsXP
        )

        try store.save(preferences)

        let reloaded = NotificationPreferencesStore(url: url).load()
        XCTAssertEqual(reloaded, preferences)
        XCTAssertEqual(reloaded.overlayScale, 1.25)
        XCTAssertEqual(reloaded.claudeCodeAnimation, .squintLegWave)
        XCTAssertEqual(reloaded.claudeCodeBubbleSkin, .windowsXP)
    }

    func testOverlayScaleClampsToSupportedRange() throws {
        var small = NotificationPreferences(overlayScale: 0.1)
        var large = NotificationPreferences(overlayScale: 4.0)

        XCTAssertEqual(small.overlayScale, NotificationPreferences.minimumOverlayScale)
        XCTAssertEqual(large.overlayScale, NotificationPreferences.maximumOverlayScale)

        small.setOverlayScale(0.25)
        large.setOverlayScale(2.5)

        XCTAssertEqual(small.overlayScale, NotificationPreferences.minimumOverlayScale)
        XCTAssertEqual(large.overlayScale, NotificationPreferences.maximumOverlayScale)
    }

    func testUpdateKeepsSingleActiveClaudeCodeAnimation() throws {
        let store = NotificationPreferencesStore(url: temporaryFile())

        let preferences = try store.update { preferences in
            preferences.selectClaudeCodeAnimation(.squintLegWave)
        }

        XCTAssertEqual(preferences.claudeCodeAnimation, .squintLegWave)
        XCTAssertEqual(store.load().claudeCodeAnimation, .squintLegWave)
    }

    func testUpdateKeepsBubbleSkinIndependentFromAnimation() throws {
        let store = NotificationPreferencesStore(url: temporaryFile())

        var preferences = try store.update { preferences in
            preferences.selectClaudeCodeAnimation(.squintLegWave)
        }

        XCTAssertEqual(preferences.claudeCodeAnimation, .squintLegWave)
        XCTAssertEqual(preferences.claudeCodeBubbleSkin, .windowsXP)

        preferences.markBubbleSkinOwned(OverlaySkin.classicPixel.rawValue)
        XCTAssertTrue(preferences.selectClaudeCodeBubbleSkin(.classicPixel))

        XCTAssertEqual(preferences.claudeCodeAnimation, .squintLegWave)
        XCTAssertEqual(preferences.claudeCodeBubbleSkin, .classicPixel)
    }

    func testPaidBubbleSkinRequiresOwnershipBeforeSelection() {
        var preferences = NotificationPreferences()

        XCTAssertFalse(preferences.selectClaudeCodeBubbleSkin(.classicPixel))
        XCTAssertEqual(preferences.claudeCodeBubbleSkin, .windowsXP)

        preferences.markBubbleSkinOwned(OverlaySkin.classicPixel.rawValue)

        XCTAssertTrue(preferences.selectClaudeCodeBubbleSkin(.classicPixel))
        XCTAssertEqual(preferences.claudeCodeBubbleSkin, .classicPixel)
    }

    func testLegacyAnimationOnlyPreferencesKeepDefaultBubbleSkin() throws {
        let url = temporaryFile()
        let legacyJSON = """
        {
          "globalEnabled": true,
          "animationEnabled": true,
          "soundEnabled": true,
          "claudeCodeAnimation": "squint-leg-wave"
        }
        """
        try Data(legacyJSON.utf8).write(to: url)

        let preferences = NotificationPreferencesStore(url: url).load()

        XCTAssertEqual(preferences.claudeCodeAnimation, .squintLegWave)
        XCTAssertEqual(preferences.claudeCodeBubbleSkin, .windowsXP)
        XCTAssertEqual(preferences.overlayScale, 1.0)
    }

    func testLegacyTemplatePreferencesMigrateToSeparateAnimationAndBubbleSkin() throws {
        let url = temporaryFile()
        let legacyJSON = """
        {
          "globalEnabled": true,
          "animationEnabled": true,
          "soundEnabled": true,
          "claudeCodeTemplateID": "claude-code-xp-squint"
        }
        """
        try Data(legacyJSON.utf8).write(to: url)

        let preferences = NotificationPreferencesStore(url: url).load()

        XCTAssertEqual(preferences.claudeCodeAnimation, .squintLegWave)
        XCTAssertEqual(preferences.claudeCodeBubbleSkin, .windowsXP)
    }

    private func temporaryFile() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("clinotify-preferences-\(UUID().uuidString).json")
    }
}
