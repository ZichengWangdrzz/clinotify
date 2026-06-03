import CLINotifyShared
import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Presents an agent event from inside the hook process. The hook has no controlling terminal (Claude
/// Code) and must not target a terminal window, so it forwards the event to the long-running daemon
/// over the Unix socket; the daemon renders the on-screen toast (and plays the sound). When the daemon
/// is unreachable, it falls back to a macOS system notification (and plays the sound CLI-side) so a
/// notification is never silently lost.
enum EventPresenter {
    static func present(_ event: AgentEvent, bypassRegistry: Bool = false) {
        let preferences = NotificationPreferencesStore().load()
        guard preferences.globalEnabled else { return }

        if deliverToDaemon(event, bypassRegistry: bypassRegistry) {
            return // The daemon owns the toast and the sound on this path.
        }

        // Fallback: no daemon running -> system notification + CLI-side sound.
        if preferences.soundEnabled {
            playSound(preferences)
        }
        postSystemNotification(
            title: "CLINotify",
            subtitle: event.displayLabel,
            body: statusText(for: event.type)
        )
    }

    /// Send the event to the daemon. Returns true only when the daemon acknowledged it (so the caller
    /// knows the toast was handled); false on any unreachable/error/negative response.
    private static func deliverToDaemon(_ event: AgentEvent, bypassRegistry: Bool) -> Bool {
        let envelope = IPCEnvelope(command: .event, event: event, bypassRegistry: bypassRegistry)
        guard let response = try? UnixSocketClient.send(envelope, waitForResponse: true) else {
            return false
        }
        return response.ok
    }

    static func statusText(for type: EventType) -> String {
        switch type {
        case .done: return "done"
        case .attention: return "needs you"
        }
    }

    static func playSound(_ preferences: NotificationPreferences) {
        let sound = preferences.selectedSoundID
            .flatMap(SoundID.init(rawValue:))
            ?? SoundCatalog.defaultSound(ownedSoundIDs: preferences.ownedSoundIDs)
        let path = "/System/Library/Sounds/\(sound.systemSoundName).aiff"
        guard FileManager.default.fileExists(atPath: path) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        process.arguments = [path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        // Not awaited: fire-and-forget; the process exits shortly after the sound finishes.
    }

    static func postSystemNotification(title: String, subtitle: String, body: String) {
        func escaped(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
        }
        let script = "display notification \"\(escaped(body))\" "
            + "with title \"\(escaped(title))\" subtitle \"\(escaped(subtitle))\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
