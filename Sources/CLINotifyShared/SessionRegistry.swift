import Foundation

public final class SessionRegistry {
    private var sessionsByTTY: [String: SessionRegistration]
    private let url: URL
    private let queue = DispatchQueue(label: "app.clinotify.session-registry")

    public init(url: URL = ApplicationPaths.registryURL) {
        self.url = url
        self.sessionsByTTY = [:]
        load()
    }

    public func register(_ registration: SessionRegistration) throws {
        try queue.sync {
            sessionsByTTY[registration.tty] = registration
            try persistLocked()
        }
    }

    public func unregister(tty: String) throws {
        try queue.sync {
            sessionsByTTY.removeValue(forKey: tty)
            try persistLocked()
        }
    }

    public func registration(for tty: String?) -> SessionRegistration? {
        guard let tty else { return nil }
        return queue.sync { sessionsByTTY[tty] }
    }

    public func allSessions() -> [SessionRegistration] {
        queue.sync {
            sessionsByTTY.values.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    private func load() {
        queue.sync {
            guard let data = try? Data(contentsOf: url) else { return }
            do {
                let sessions = try JSONDecoder.clinotify.decode([SessionRegistration].self, from: data)
                sessionsByTTY = Dictionary(uniqueKeysWithValues: sessions.map { ($0.tty, $0) })
            } catch {
                sessionsByTTY = [:]
            }
        }
    }

    private func persistLocked() throws {
        try ApplicationPaths.ensureApplicationSupportDirectory()
        let sessions = sessionsByTTY.values.sorted { $0.tty < $1.tty }
        let data = try JSONEncoder.clinotify.encode(sessions)
        try data.write(to: url, options: .atomic)
    }
}
