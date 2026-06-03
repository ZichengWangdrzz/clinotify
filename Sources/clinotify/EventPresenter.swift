import CLINotifyShared
import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Presents an agent event from inside the hook process. The hook has no controlling terminal (Claude
/// Code) and must not target a terminal window, so it forwards the event to the long-running daemon
/// over the Unix socket; the daemon renders the on-screen toast (and plays the sound). When the daemon
/// is unreachable, the only fallback is a CLI-side sound — macOS system banner notifications are
/// intentionally NOT used (CLINotify is a toast-only product).
enum EventPresenter {
    static func present(_ event: AgentEvent, bypassRegistry: Bool = false) {
        let preferences = NotificationPreferencesStore().load()
        guard preferences.globalEnabled else { return }

        if deliverToDaemon(event, bypassRegistry: bypassRegistry) {
            return // The daemon owns the toast and the sound on this path.
        }

        // Fallback when no daemon is running: a CLI-side sound only. No system banner by design.
        if preferences.soundEnabled {
            playSound(preferences)
        }
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
}
