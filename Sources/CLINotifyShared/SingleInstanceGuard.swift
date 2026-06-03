import Darwin
import Foundation
import os

/// Guarantees a single running CLINotify helper. Holds an exclusive advisory lock (`flock`) on a lock
/// file for the whole process lifetime. The kernel releases the lock automatically when the process
/// exits OR crashes, so a dead helper never blocks a new one — but a live (even hung) helper does,
/// which is exactly the "only one at a time" guarantee. The held descriptor is intentionally kept open
/// for the process lifetime; production code never calls `release()` (the OS reclaims it on exit).
public final class SingleInstanceGuard {
    private static let logger = Logger(subsystem: "app.clinotify", category: "single-instance")
    private var lockDescriptor: Int32 = -1
    private let path: String

    public init(path: String = ApplicationPaths.lockPath) {
        self.path = path
    }

    /// Try to become the sole helper. Returns true if this process now holds the lock (or if the lock
    /// file could not be created at all — fail-open so the only helper still starts).
    public func acquire() -> Bool {
        try? ApplicationPaths.ensureApplicationSupportDirectory()
        let descriptor = open(path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else {
            Self.logger.error("Lock file unavailable at \(self.path, privacy: .public); proceeding without the guard.")
            return true
        }
        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            // EWOULDBLOCK: another live helper already holds the exclusive lock.
            close(descriptor)
            return false
        }
        lockDescriptor = descriptor // hold for the process lifetime
        return true
    }

    /// Release the lock (closes the descriptor). Production never calls this — it exists for tests and
    /// for symmetry. Safe to call when no lock is held.
    public func release() {
        if lockDescriptor >= 0 {
            close(lockDescriptor)
            lockDescriptor = -1
        }
    }
}
