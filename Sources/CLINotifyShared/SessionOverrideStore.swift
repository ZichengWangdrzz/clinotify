import Foundation

/// Daemon-owned persistence for per-terminal (per-TTY) preference overrides.
///
/// Thread-safe via a serial queue (mirroring `SessionRegistry`), so it integrates with the
/// synchronous IPC handler and event router without actor-bridging. Empty overrides are pruned so
/// the on-disk dictionary only holds meaningful entries.
public final class SessionOverrideStore {
    private var overridesByTTY: [String: SessionPreferenceOverride]
    private let url: URL
    private let queue = DispatchQueue(label: "app.clinotify.session-overrides")

    public init(url: URL = ApplicationPaths.sessionOverridesURL) {
        self.url = url
        self.overridesByTTY = Self.load(url: url)
    }

    public func override(for tty: String) -> SessionPreferenceOverride? {
        queue.sync { overridesByTTY[tty] }
    }

    public func all() -> [String: SessionPreferenceOverride] {
        queue.sync { overridesByTTY }
    }

    /// Replace the override for `tty`. Empty overrides are removed.
    @discardableResult
    public func set(tty: String, override: SessionPreferenceOverride) throws -> SessionPreferenceOverride {
        try queue.sync {
            store(tty: tty, override: override)
            try persistLocked()
            return override
        }
    }

    /// Merge `delta` over the existing override for `tty` (delta fields win). Empty results are removed.
    @discardableResult
    public func merge(tty: String, delta: SessionPreferenceOverride) throws -> SessionPreferenceOverride {
        try queue.sync {
            let merged = (overridesByTTY[tty] ?? SessionPreferenceOverride()).merging(delta)
            store(tty: tty, override: merged)
            try persistLocked()
            return merged
        }
    }

    /// Apply a transform to the override for `tty` (creating an empty one if absent). Empty results are removed.
    @discardableResult
    public func update(
        tty: String,
        _ transform: (inout SessionPreferenceOverride) -> Void
    ) throws -> SessionPreferenceOverride {
        try queue.sync {
            var override = overridesByTTY[tty] ?? SessionPreferenceOverride()
            transform(&override)
            store(tty: tty, override: override)
            try persistLocked()
            return override
        }
    }

    public func clear(tty: String) throws {
        try queue.sync {
            overridesByTTY.removeValue(forKey: tty)
            try persistLocked()
        }
    }

    private func store(tty: String, override: SessionPreferenceOverride) {
        if override.isEmpty {
            overridesByTTY.removeValue(forKey: tty)
        } else {
            overridesByTTY[tty] = override
        }
    }

    private static func load(url: URL) -> [String: SessionPreferenceOverride] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder.clinotify.decode([String: SessionPreferenceOverride].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private func persistLocked() throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.clinotify.encode(overridesByTTY)
        try data.write(to: url, options: [.atomic])
    }
}
