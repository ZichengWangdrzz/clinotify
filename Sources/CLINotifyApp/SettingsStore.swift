import AppKit
import CLINotifyShared
import Combine
import Foundation

final class SettingsStore: ObservableObject {
    @Published var globalEnabled: Bool {
        didSet {
            defaults.set(globalEnabled, forKey: Keys.globalEnabled)
            persistNotificationPreferences()
        }
    }

    @Published var animationEnabled: Bool {
        didSet {
            defaults.set(animationEnabled, forKey: Keys.animationEnabled)
            persistNotificationPreferences()
        }
    }

    @Published var soundEnabled: Bool {
        didSet {
            defaults.set(soundEnabled, forKey: Keys.soundEnabled)
            persistNotificationPreferences()
        }
    }

    @Published var overlayScale: Double {
        didSet {
            defaults.set(NotificationPreferences.clampedOverlayScale(overlayScale), forKey: Keys.overlayScale)
            persistNotificationPreferences()
        }
    }

    @Published var selectedClaudeCodeAnimation: String {
        didSet {
            defaults.set(selectedClaudeCodeAnimation, forKey: Keys.selectedClaudeCodeAnimation)
            persistNotificationPreferences()
        }
    }

    @Published var selectedClaudeCodeBubbleSkin: String {
        didSet {
            defaults.set(selectedClaudeCodeBubbleSkin, forKey: Keys.selectedClaudeCodeBubbleSkin)
            persistNotificationPreferences()
        }
    }

    @Published var selectedClaudeCodeFrameSkin: String {
        didSet {
            defaults.set(selectedClaudeCodeFrameSkin, forKey: Keys.selectedClaudeCodeFrameSkin)
            persistNotificationPreferences()
        }
    }

    @Published var selectedScreenID: String {
        didSet { defaults.set(selectedScreenID, forKey: Keys.selectedScreenID) }
    }

    @Published var doneSoundName: String {
        didSet { defaults.set(doneSoundName, forKey: Keys.doneSoundName) }
    }

    @Published var attentionSoundName: String {
        didSet { defaults.set(attentionSoundName, forKey: Keys.attentionSoundName) }
    }

    @Published var doneCustomSoundPath: String {
        didSet { defaults.set(doneCustomSoundPath, forKey: Keys.doneCustomSoundPath) }
    }

    @Published var attentionCustomSoundPath: String {
        didSet { defaults.set(attentionCustomSoundPath, forKey: Keys.attentionCustomSoundPath) }
    }

    private let defaults: UserDefaults
    private let preferencesStore: NotificationPreferencesStore

    init(defaults: UserDefaults = .standard, preferencesStore: NotificationPreferencesStore = NotificationPreferencesStore()) {
        self.defaults = defaults
        self.preferencesStore = preferencesStore
        let notificationPreferences = preferencesStore.load()
        self.globalEnabled = notificationPreferences.globalEnabled
        self.animationEnabled = notificationPreferences.animationEnabled
        self.soundEnabled = notificationPreferences.soundEnabled
        self.overlayScale = notificationPreferences.overlayScale
        self.selectedClaudeCodeAnimation = notificationPreferences.claudeCodeAnimation.rawValue
        self.selectedClaudeCodeBubbleSkin = notificationPreferences.claudeCodeBubbleSkin.rawValue
        self.selectedClaudeCodeFrameSkin = notificationPreferences.claudeCodeFrameSkin.rawValue
        self.selectedScreenID = defaults.string(forKey: Keys.selectedScreenID) ?? ScreenChoice.primary.rawValue
        self.doneSoundName = defaults.string(forKey: Keys.doneSoundName) ?? "Glass"
        self.attentionSoundName = defaults.string(forKey: Keys.attentionSoundName) ?? "Ping"
        self.doneCustomSoundPath = defaults.string(forKey: Keys.doneCustomSoundPath) ?? ""
        self.attentionCustomSoundPath = defaults.string(forKey: Keys.attentionCustomSoundPath) ?? ""
        persistNotificationPreferences()
    }

    func notificationPreferences() -> NotificationPreferences {
        preferencesStore.load()
    }

    func availableClaudeCodeAnimations() -> [ClaudeCodeAnimation] {
        AnimationCatalog.availableClaudeCodeAnimations(
            ownedAnimationIDs: notificationPreferences().ownedAnimationIDs
        ).map(\.id)
    }

    func selectedClaudeCodeAnimationValue() -> ClaudeCodeAnimation {
        ClaudeCodeAnimation(rawValue: selectedClaudeCodeAnimation) ?? .rightHandWave
    }

    func availableClaudeCodeBubbleSkins() -> [OverlaySkin] {
        BubbleSkinCatalog.availableClaudeCodeSkins(
            ownedSkinIDs: notificationPreferences().ownedBubbleSkinIDs
        ).map(\.id)
    }

    func selectedClaudeCodeBubbleSkinValue() -> OverlaySkin {
        OverlaySkin(rawValue: selectedClaudeCodeBubbleSkin) ?? .windowsXP
    }

    func availableClaudeCodeFrames() -> [FrameSkin] {
        FrameCatalog.availableClaudeCodeFrames(
            ownedFrameSkinIDs: notificationPreferences().ownedFrameSkinIDs
        ).map(\.id)
    }

    func selectedClaudeCodeFrameSkinValue() -> FrameSkin {
        FrameSkin(rawValue: selectedClaudeCodeFrameSkin) ?? .panel
    }

    func targetScreen(capabilities: LicenseCapabilities) -> NSScreen {
        if !capabilities.displaySelection || selectedScreenID == ScreenChoice.primary.rawValue {
            // PRIMARY = the menu-bar display (origin == 0,0), NOT NSScreen.main (the focused screen).
            return NSScreen.primaryDisplay
        }
        return NSScreen.screens.first { screen in
            screen.displayIDString == selectedScreenID
        } ?? NSScreen.primaryDisplay
    }

    func availableScreens() -> [(id: String, title: String)] {
        let screens = NSScreen.screens.enumerated().map { index, screen in
            let id = screen.displayIDString
            let title = screen == NSScreen.main ? "Main Display" : "Display \(index + 1)"
            return (id: id, title: title)
        }
        return [(id: ScreenChoice.primary.rawValue, title: "Primary Display")] + screens
    }

    func customSoundURL(for type: EventType) -> URL? {
        let path = type == .done ? doneCustomSoundPath : attentionCustomSoundPath
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    func setCustomSound(url: URL?, for type: EventType) {
        let path = url?.path ?? ""
        switch type {
        case .done:
            doneCustomSoundPath = path
        case .attention:
            attentionCustomSoundPath = path
        }
    }

    private func persistNotificationPreferences() {
        let current = preferencesStore.load()
        var preferences = NotificationPreferences(
            globalEnabled: globalEnabled,
            animationEnabled: animationEnabled,
            soundEnabled: soundEnabled,
            overlayScale: NotificationPreferences.clampedOverlayScale(overlayScale),
            claudeCodeAnimation: selectedClaudeCodeAnimationValue(),
            claudeCodeBubbleSkin: selectedClaudeCodeBubbleSkinValue(),
            claudeCodeFrameSkin: selectedClaudeCodeFrameSkinValue(),
            ownedAnimationIDs: current.ownedAnimationIDs,
            ownedBubbleSkinIDs: current.ownedBubbleSkinIDs,
            ownedFrameSkinIDs: current.ownedFrameSkinIDs
        )
        _ = preferences.selectClaudeCodeAnimation(selectedClaudeCodeAnimationValue())
        _ = preferences.selectClaudeCodeBubbleSkin(selectedClaudeCodeBubbleSkinValue())
        _ = preferences.selectClaudeCodeFrameSkin(selectedClaudeCodeFrameSkinValue())
        try? preferencesStore.save(preferences)
    }
}

private enum Keys {
    static let globalEnabled = "globalEnabled"
    static let animationEnabled = "animationEnabled"
    static let soundEnabled = "soundEnabled"
    static let overlayScale = "overlayScale"
    static let selectedClaudeCodeAnimation = "selectedClaudeCodeAnimation"
    static let selectedClaudeCodeBubbleSkin = "selectedClaudeCodeBubbleSkin"
    static let selectedClaudeCodeFrameSkin = "selectedClaudeCodeFrameSkin"
    static let selectedScreenID = "selectedScreenID"
    static let doneSoundName = "doneSoundName"
    static let attentionSoundName = "attentionSoundName"
    static let doneCustomSoundPath = "doneCustomSoundPath"
    static let attentionCustomSoundPath = "attentionCustomSoundPath"
}

private enum ScreenChoice: String {
    case primary
}

private extension NSScreen {
    var displayIDString: String {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return localizedName
        }
        return number.stringValue
    }
}
