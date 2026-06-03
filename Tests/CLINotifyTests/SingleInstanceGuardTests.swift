import Foundation
import XCTest
@testable import CLINotifyShared

final class SingleInstanceGuardTests: XCTestCase {
    private func temporaryLockPath() -> String {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("clinotify-lock-\(UUID().uuidString).lock")
            .path
    }

    func testSecondInstanceIsRefusedWhileFirstHoldsTheLock() {
        let path = temporaryLockPath()
        let first = SingleInstanceGuard(path: path)
        let second = SingleInstanceGuard(path: path)
        defer { first.release(); second.release() }

        XCTAssertTrue(first.acquire(), "the first instance must acquire the lock")
        XCTAssertFalse(second.acquire(), "a second instance must be refused while the first holds the lock")
    }

    func testLockIsReusableAfterTheHolderReleases() {
        let path = temporaryLockPath()
        let first = SingleInstanceGuard(path: path)
        XCTAssertTrue(first.acquire())
        first.release() // simulates the holder exiting/crashing (kernel frees the flock)

        let next = SingleInstanceGuard(path: path)
        defer { next.release() }
        XCTAssertTrue(next.acquire(), "a fresh instance must acquire once the prior holder is gone")
    }

    func testReleaseIsIdempotentAndSafeWithoutAcquire() {
        let guard1 = SingleInstanceGuard(path: temporaryLockPath())
        guard1.release() // never acquired -> must not crash
        XCTAssertTrue(guard1.acquire())
        guard1.release()
        guard1.release() // double release -> must not crash
    }
}
