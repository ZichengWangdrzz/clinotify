import AppKit
import AVFoundation
import CLINotifyShared
import Foundation

final class SoundManager {
    private var players: [AVAudioPlayer] = []

    func play(
        for event: AgentEvent,
        settings: SettingsStore,
        capabilities: LicenseCapabilities,
        preferences: NotificationPreferences
    ) {
        // A selected catalog sound (per-terminal or global) takes priority when owned/available.
        if let selectedID = preferences.selectedSoundID,
           let sound = SoundID(rawValue: selectedID),
           SoundCatalog.isSoundAvailable(sound, ownedSoundIDs: preferences.ownedSoundIDs) {
            NSSound(named: NSSound.Name(sound.systemSoundName))?.play()
            return
        }

        if capabilities.customSounds,
           let url = settings.customSoundURL(for: event.type),
           FileManager.default.fileExists(atPath: url.path),
           let player = try? AVAudioPlayer(contentsOf: url) {
            player.prepareToPlay()
            player.play()
            players.append(player)
            players.removeAll { !$0.isPlaying }
            return
        }
        let name = event.type == .done ? settings.doneSoundName : settings.attentionSoundName
        NSSound(named: NSSound.Name(name))?.play()
    }
}
