import XCTest
@testable import CLINotifyShared

final class SessionPreferenceOverrideTests: XCTestCase {
    func testEmptyDetection() {
        XCTAssertTrue(SessionPreferenceOverride().isEmpty)
        XCTAssertFalse(SessionPreferenceOverride(soundMuted: true).isEmpty)
        XCTAssertFalse(SessionPreferenceOverride(animationEnabled: false).isEmpty)
        XCTAssertFalse(SessionPreferenceOverride(selectedSoundID: "ping").isEmpty)
    }

    func testMergingPrefersDeltaFields() {
        let base = SessionPreferenceOverride(soundMuted: true, animationEnabled: true)
        let delta = SessionPreferenceOverride(soundMuted: false, selectedSoundID: "ping")
        let merged = base.merging(delta)
        XCTAssertEqual(merged.soundMuted, false) // delta wins
        XCTAssertEqual(merged.animationEnabled, true) // base retained where delta is nil
        XCTAssertEqual(merged.selectedSoundID, "ping")
    }

    func testResolvedMutesSoundWithoutMutatingGlobal() {
        let global = NotificationPreferences(soundEnabled: true)
        let override = SessionPreferenceOverride(soundMuted: true)
        let resolved = override.resolved(global: global)
        XCTAssertFalse(resolved.soundEnabled)
        XCTAssertTrue(global.soundEnabled, "global must be untouched")
    }

    func testResolvedUnmuteRespectsGloballyDisabledSound() {
        let global = NotificationPreferences(soundEnabled: false)
        let resolved = SessionPreferenceOverride(soundMuted: false).resolved(global: global)
        XCTAssertFalse(resolved.soundEnabled, "unmute cannot enable a globally-off sound")
    }

    func testResolvedAnimationToggle() {
        let global = NotificationPreferences(animationEnabled: true)
        let resolved = SessionPreferenceOverride(animationEnabled: false).resolved(global: global)
        XCTAssertFalse(resolved.animationEnabled)
        XCTAssertTrue(global.animationEnabled)
    }

    func testResolvedSkinSwapGatedByOwnership() {
        // classic-pixel is a paid skin; without ownership the override is ignored.
        let lockedGlobal = NotificationPreferences(ownedBubbleSkinIDs: [])
        let lockedResolved = SessionPreferenceOverride(claudeCodeBubbleSkin: .classicPixel)
            .resolved(global: lockedGlobal)
        XCTAssertEqual(lockedResolved.claudeCodeBubbleSkin, .windowsXP)

        let ownedGlobal = NotificationPreferences(ownedBubbleSkinIDs: [OverlaySkin.classicPixel.rawValue])
        let ownedResolved = SessionPreferenceOverride(claudeCodeBubbleSkin: .classicPixel)
            .resolved(global: ownedGlobal)
        XCTAssertEqual(ownedResolved.claudeCodeBubbleSkin, .classicPixel)
    }

    func testMergingPrefersClaudeCodeAnimationDelta() {
        // Exercises the generic delta-wins merge plumbing with a field that still has >1 value.
        let base = SessionPreferenceOverride(claudeCodeAnimation: .rightHandWave)
        let delta = SessionPreferenceOverride(claudeCodeAnimation: .squintLegWave)
        XCTAssertEqual(base.merging(delta).claudeCodeAnimation, .squintLegWave)
        XCTAssertEqual(delta.merging(SessionPreferenceOverride()).claudeCodeAnimation, .squintLegWave,
                       "unset delta field retains base value")
    }

    func testCodableRoundTrip() throws {
        let override = SessionPreferenceOverride(
            soundMuted: true,
            animationEnabled: false,
            claudeCodeAnimation: .squintLegWave,
            claudeCodeBubbleSkin: .windowsXP,
            selectedSoundID: "ping"
        )
        let data = try JSONEncoder.clinotify.encode(override)
        let decoded = try JSONDecoder.clinotify.decode(SessionPreferenceOverride.self, from: data)
        XCTAssertEqual(decoded, override)
    }

    func testDecodesSparseJSON() throws {
        let json = Data(#"{"soundMuted": true}"#.utf8)
        let decoded = try JSONDecoder.clinotify.decode(SessionPreferenceOverride.self, from: json)
        XCTAssertEqual(decoded.soundMuted, true)
        XCTAssertNil(decoded.animationEnabled)
        XCTAssertNil(decoded.selectedSoundID)
    }
}
