import XCTest
@testable import CLINotifyShared

final class AnimationAssetTests: XCTestCase {
    func testClaudePixelAnimationsKeepTwoSecondCycleButLongerDisplayLifetime() {
        for animation in ClaudeCodeAnimation.allCases {
            let asset = AnimationAsset.claudeCode(animation)

            XCTAssertTrue(asset.loop)
            XCTAssertEqual(asset.duration, 2.0)
            XCTAssertGreaterThan(asset.displayDuration, asset.duration)
            XCTAssertEqual(asset.frameRate, 120)
        }
    }

    func testClaudePreferencesResolveAnimationAssetIndependentlyFromBubbleSkin() {
        let preferences = NotificationPreferences(
            claudeCodeAnimation: .squintLegWave,
            claudeCodeBubbleSkin: .windowsXP
        )

        let asset = AnimationAsset.asset(source: .claudeCode, type: .done, preferences: preferences)

        XCTAssertEqual(asset.renderer, .claudePixelSquintLegWave)
        XCTAssertEqual(asset.bundledFilename, "Claude-Pixel-Squint-Leg-Wave-120fps.mp4")
    }

    func testPreferencesSelectDefaultAnimationAndBubbleSkinSeparately() {
        let preferences = NotificationPreferences.defaultValue

        let asset = AnimationAsset.asset(source: .claudeCode, type: .done, preferences: preferences)
        let skin = BubbleSkinCatalog.selectedSkin(for: .claudeCode, preferences: preferences)

        XCTAssertEqual(asset.renderer, .claudePixelRightHandWave)
        XCTAssertEqual(skin, .windowsXP)
    }
}
