import XCTest
@testable import CLINotifyShared

final class SoundCatalogTests: XCTestCase {
    func testFreeSoundsAvailableWithoutOwnership() {
        XCTAssertTrue(SoundCatalog.isSoundAvailable(.glass, ownedSoundIDs: []))
        XCTAssertTrue(SoundCatalog.isSoundAvailable(.ping, ownedSoundIDs: []))
    }

    func testPaidSoundLockedUntilOwned() {
        XCTAssertFalse(SoundCatalog.isSoundAvailable(.arcadeChime, ownedSoundIDs: []))
        XCTAssertTrue(SoundCatalog.isSoundAvailable(.arcadeChime, ownedSoundIDs: [SoundID.arcadeChime.rawValue]))
    }

    func testAvailableSoundsFiltersByOwnership() {
        let free = SoundCatalog.availableSounds(ownedSoundIDs: [])
        XCTAssertFalse(free.contains { $0.id == .arcadeChime })
        let owned = SoundCatalog.availableSounds(ownedSoundIDs: [SoundID.arcadeChime.rawValue])
        XCTAssertTrue(owned.contains { $0.id == .arcadeChime })
    }

    func testDefaultSoundIsFirstFree() {
        XCTAssertEqual(SoundCatalog.defaultSound(ownedSoundIDs: []), .glass)
    }

    func testSelectSoundGatedByOwnership() {
        var locked = NotificationPreferences(ownedSoundIDs: [])
        XCTAssertFalse(locked.selectSound(.arcadeChime))
        XCTAssertNil(locked.selectedSoundID)
        XCTAssertTrue(locked.selectSound(.ping))
        XCTAssertEqual(locked.selectedSoundID, SoundID.ping.rawValue)

        var owned = NotificationPreferences(ownedSoundIDs: [SoundID.arcadeChime.rawValue])
        XCTAssertTrue(owned.selectSound(.arcadeChime))
        XCTAssertEqual(owned.selectedSoundID, SoundID.arcadeChime.rawValue)
    }

    func testOverrideResolvesSelectedSoundGated() {
        let global = NotificationPreferences(ownedSoundIDs: [])
        let lockedResolved = SessionPreferenceOverride(selectedSoundID: SoundID.arcadeChime.rawValue)
            .resolved(global: global)
        XCTAssertNil(lockedResolved.selectedSoundID, "locked paid sound is ignored")

        let freeResolved = SessionPreferenceOverride(selectedSoundID: SoundID.ping.rawValue)
            .resolved(global: global)
        XCTAssertEqual(freeResolved.selectedSoundID, SoundID.ping.rawValue)
    }
}
