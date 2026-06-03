import Foundation
import XCTest
@testable import CLINotifyShared

final class LicenseManagerTests: XCTestCase {
    func testFreeAndExpiredCapabilitiesDisablePaidFeatures() throws {
        let manager = LicenseManager(cacheURL: temporaryFile())
        XCTAssertEqual(manager.record.state, .free)
        XCTAssertEqual(manager.capabilities, .free)

        try manager.cache(LicenseRecord(state: .expired))
        XCTAssertEqual(manager.capabilities, .free)
    }

    func testFreeTierIncludesBaseOverlayButNotPremiumContent() throws {
        // Product decision: the base overlay (anchored glass + default animation + default bubble)
        // is free for everyone; only custom sound files and multi-display selection are paid, with
        // swappable skins/premium sounds gated per-entry by ownership in the catalogs.
        XCTAssertTrue(LicenseCapabilities.free.mascotAnimation)
        XCTAssertTrue(LicenseCapabilities.free.sessionBubble)
        XCTAssertFalse(LicenseCapabilities.free.customSounds)
        XCTAssertFalse(LicenseCapabilities.free.displaySelection)
    }

    func testSubscriptionAndLifetimeCapabilitiesEnablePaidFeatures() throws {
        let manager = LicenseManager(cacheURL: temporaryFile())
        try manager.cache(LicenseRecord(state: .activeSubscription))
        XCTAssertEqual(manager.capabilities, .paid)

        try manager.cache(LicenseRecord(state: .lifetime))
        XCTAssertEqual(manager.capabilities, .paid)
    }

    func testActivateCachedStoresKeyTailAndState() throws {
        let cacheURL = temporaryFile()
        let manager = LicenseManager(cacheURL: cacheURL)

        try manager.activateCached(key: "LS-EXAMPLE-LIFE-123456", state: .lifetime)

        let reloaded = LicenseManager(cacheURL: cacheURL)
        XCTAssertEqual(reloaded.record.state, .lifetime)
        XCTAssertEqual(reloaded.record.licenseKeyTail, "123456")
        XCTAssertEqual(reloaded.capabilities, .paid)
    }

    func testReloadFromDiskPicksUpExternalCacheWrites() throws {
        let cacheURL = temporaryFile()
        let manager = LicenseManager(cacheURL: cacheURL)
        XCTAssertEqual(manager.capabilities, .free)

        let externalWriter = LicenseManager(cacheURL: cacheURL)
        try externalWriter.cache(LicenseRecord(state: .lifetime))

        manager.reloadFromDisk()
        XCTAssertEqual(manager.record.state, .lifetime)
        XCTAssertEqual(manager.capabilities, .paid)
    }

    private func temporaryFile() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("clinotify-license-\(UUID().uuidString).json")
    }
}
