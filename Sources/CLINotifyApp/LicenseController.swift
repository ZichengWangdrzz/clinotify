import CLINotifyShared
import Combine
import Foundation

final class LicenseController: ObservableObject {
    @Published private(set) var record: LicenseRecord
    private let manager: LicenseManager

    init(manager: LicenseManager = LicenseManager()) {
        self.manager = manager
        self.record = manager.record
    }

    var capabilities: LicenseCapabilities {
        manager.capabilities
    }

    func refreshFromDisk() -> LicenseCapabilities {
        manager.reloadFromDisk()
        let refreshedRecord = manager.record
        if Thread.isMainThread {
            record = refreshedRecord
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.record = refreshedRecord
            }
        }
        return manager.capabilities
    }

    var statusText: String {
        switch record.state {
        case .free:
            return "Free"
        case .activeSubscription:
            return "Subscription active"
        case .lifetime:
            return "Lifetime active"
        case .expired:
            return "Expired"
        }
    }

    func activateLocal(key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let state: LicenseState = trimmed.uppercased().contains("LIFE") ? .lifetime : .activeSubscription
        try manager.activateCached(key: trimmed, state: state)
        record = manager.record
    }

    func activateOnline(key: String) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let instanceName = Host.current().localizedName ?? "CLINotify Mac"
        try await manager.activateOnline(key: trimmed, instanceName: instanceName)
        await MainActor.run {
            record = manager.record
        }
    }

    func resetToFree() throws {
        try manager.resetToFree()
        record = manager.record
    }
}
