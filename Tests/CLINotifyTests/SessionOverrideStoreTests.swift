import Foundation
import XCTest
@testable import CLINotifyShared

final class SessionOverrideStoreTests: XCTestCase {
    func testSetPersistsAndReloads() throws {
        let url = temporaryURL()
        let store = SessionOverrideStore(url: url)
        try store.set(tty: "ttys001", override: SessionPreferenceOverride(soundMuted: true))

        let reloaded = SessionOverrideStore(url: url)
        XCTAssertEqual(reloaded.override(for: "ttys001")?.soundMuted, true)
    }

    func testMergeKeepsExistingFields() throws {
        let store = SessionOverrideStore(url: temporaryURL())
        try store.set(tty: "ttys001", override: SessionPreferenceOverride(soundMuted: true))
        let merged = try store.merge(tty: "ttys001", delta: SessionPreferenceOverride(animationEnabled: false))
        XCTAssertEqual(merged.soundMuted, true)
        XCTAssertEqual(merged.animationEnabled, false)
    }

    func testUpdateTransform() throws {
        let store = SessionOverrideStore(url: temporaryURL())
        try store.update(tty: "ttys002") { $0.soundMuted = true }
        XCTAssertEqual(store.override(for: "ttys002")?.soundMuted, true)
    }

    func testEmptyOverrideIsPruned() throws {
        let store = SessionOverrideStore(url: temporaryURL())
        try store.set(tty: "ttys003", override: SessionPreferenceOverride())
        XCTAssertNil(store.override(for: "ttys003"))
    }

    func testClearRemovesEntry() throws {
        let store = SessionOverrideStore(url: temporaryURL())
        try store.set(tty: "ttys004", override: SessionPreferenceOverride(soundMuted: true))
        try store.clear(tty: "ttys004")
        XCTAssertNil(store.override(for: "ttys004"))
    }

    func testIndependentTTYsDoNotBleed() throws {
        let store = SessionOverrideStore(url: temporaryURL())
        try store.set(tty: "ttys005", override: SessionPreferenceOverride(soundMuted: true))
        try store.set(tty: "ttys006", override: SessionPreferenceOverride(animationEnabled: false))
        XCTAssertEqual(store.override(for: "ttys005")?.soundMuted, true)
        XCTAssertNil(store.override(for: "ttys005")?.animationEnabled)
        XCTAssertEqual(store.override(for: "ttys006")?.animationEnabled, false)
        XCTAssertNil(store.override(for: "ttys006")?.soundMuted)
    }

    private func temporaryURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("clinotify-overrides-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("session-overrides.json")
    }
}
