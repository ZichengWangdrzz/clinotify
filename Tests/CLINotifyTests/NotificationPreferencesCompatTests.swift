import Foundation
import XCTest
@testable import CLINotifyShared

final class NotificationPreferencesCompatTests: XCTestCase {
    func testOldPreferencesDecodeWithDefaultsForNewFields() throws {
        // An old preferences.json that predates ownedSoundIDs / selectedSoundID.
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
        XCTAssertEqual(decoded.ownedSoundIDs, [])
        XCTAssertNil(decoded.selectedSoundID)
    }

    func testLegacyOverlayKeysAreIgnoredAndDecode() throws {
        // Prefs written by a pre-toast build still carry the retired `overlayPresentation` /
        // `overlayPlacement` keys. Because the decoder ignores unknown keys, such a blob must still
        // decode without throwing (backward compatibility).
        let json = Data(#"""
        {
          "globalEnabled": true,
          "animationEnabled": true,
          "soundEnabled": true,
          "overlayScale": 1.0,
          "claudeCodeAnimation": "right-hand-wave",
          "overlayPresentation": "macos",
          "overlayPlacement": { "position": "top", "size": "large" },
          "ownedAnimationIDs": [],
          "ownedBubbleSkinIDs": []
        }
        """#.utf8)
        let decoded = try JSONDecoder.clinotify.decode(NotificationPreferences.self, from: json)
        XCTAssertTrue(decoded.globalEnabled)
        XCTAssertEqual(decoded.claudeCodeAnimation, .rightHandWave)
    }

    func testNewFieldsRoundTrip() throws {
        let preferences = NotificationPreferences(
            ownedSoundIDs: [SoundID.arcadeChime.rawValue],
            selectedSoundID: SoundID.arcadeChime.rawValue
        )
        let data = try JSONEncoder.clinotify.encode(preferences)
        let decoded = try JSONDecoder.clinotify.decode(NotificationPreferences.self, from: data)
        XCTAssertEqual(decoded.selectedSoundID, SoundID.arcadeChime.rawValue)
        XCTAssertTrue(decoded.ownedSoundIDs.contains(SoundID.arcadeChime.rawValue))
    }

    func testSelectedSoundDroppedIfUnowned() throws {
        // selectedSoundID points to a paid sound that is not owned -> dropped on init.
        let preferences = NotificationPreferences(
            ownedSoundIDs: [],
            selectedSoundID: SoundID.arcadeChime.rawValue
        )
        XCTAssertNil(preferences.selectedSoundID)
    }
}
