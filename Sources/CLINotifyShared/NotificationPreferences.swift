import Foundation

public enum ClaudeCodeAnimation: String, Codable, CaseIterable, Sendable {
    case rightHandWave = "right-hand-wave"
    case squintLegWave = "squint-leg-wave"

    public var title: String {
        switch self {
        case .rightHandWave:
            return "Right hand wave"
        case .squintLegWave:
            return "Squint leg wave"
        }
    }
}

public struct NotificationPreferences: Codable, Equatable, Sendable {
    public static let minimumOverlayScale = 0.5
    public static let maximumOverlayScale = 2.0

    public var globalEnabled: Bool
    public var animationEnabled: Bool
    public var soundEnabled: Bool
    public var overlayScale: Double
    public var claudeCodeAnimation: ClaudeCodeAnimation
    public var claudeCodeBubbleSkin: OverlaySkin
    public var claudeCodeFrameSkin: FrameSkin
    public var ownedAnimationIDs: Set<String>
    public var ownedBubbleSkinIDs: Set<String>
    public var ownedFrameSkinIDs: Set<String>
    public var ownedSoundIDs: Set<String>
    public var selectedSoundID: String?

    public init(
        globalEnabled: Bool = true,
        animationEnabled: Bool = true,
        soundEnabled: Bool = true,
        overlayScale: Double = 1.0,
        claudeCodeAnimation: ClaudeCodeAnimation = .rightHandWave,
        claudeCodeBubbleSkin: OverlaySkin = .windowsXP,
        claudeCodeFrameSkin: FrameSkin = .panel,
        ownedAnimationIDs: Set<String> = [],
        ownedBubbleSkinIDs: Set<String> = [],
        ownedFrameSkinIDs: Set<String> = [],
        ownedSoundIDs: Set<String> = [],
        selectedSoundID: String? = nil
    ) {
        self.globalEnabled = globalEnabled
        self.animationEnabled = animationEnabled
        self.soundEnabled = soundEnabled
        self.overlayScale = Self.clampedOverlayScale(overlayScale)
        self.ownedAnimationIDs = ownedAnimationIDs
        self.ownedBubbleSkinIDs = ownedBubbleSkinIDs
        self.ownedFrameSkinIDs = ownedFrameSkinIDs
        self.ownedSoundIDs = ownedSoundIDs
        self.claudeCodeAnimation = AnimationCatalog.isClaudeCodeAnimationAvailable(
            claudeCodeAnimation,
            ownedAnimationIDs: ownedAnimationIDs
        )
            ? claudeCodeAnimation
            : AnimationCatalog.defaultClaudeCodeAnimation(ownedAnimationIDs: ownedAnimationIDs)
        self.claudeCodeBubbleSkin = BubbleSkinCatalog.isClaudeCodeSkinAvailable(
            claudeCodeBubbleSkin,
            ownedSkinIDs: ownedBubbleSkinIDs
        )
            ? claudeCodeBubbleSkin
            : BubbleSkinCatalog.defaultClaudeCodeSkin(ownedSkinIDs: ownedBubbleSkinIDs)
        self.claudeCodeFrameSkin = FrameCatalog.isClaudeCodeFrameAvailable(
            claudeCodeFrameSkin,
            ownedFrameSkinIDs: ownedFrameSkinIDs
        )
            ? claudeCodeFrameSkin
            : FrameCatalog.defaultClaudeCodeFrame(ownedFrameSkinIDs: ownedFrameSkinIDs)
        if let selectedSoundID,
           let sound = SoundID(rawValue: selectedSoundID),
           SoundCatalog.isSoundAvailable(sound, ownedSoundIDs: ownedSoundIDs) {
            self.selectedSoundID = selectedSoundID
        } else {
            self.selectedSoundID = nil
        }
    }

    public static let defaultValue = NotificationPreferences()

    @discardableResult
    public mutating func selectClaudeCodeAnimation(_ animation: ClaudeCodeAnimation) -> Bool {
        guard AnimationCatalog.isClaudeCodeAnimationAvailable(animation, ownedAnimationIDs: ownedAnimationIDs) else {
            return false
        }
        claudeCodeAnimation = animation
        return true
    }

    @discardableResult
    public mutating func selectClaudeCodeBubbleSkin(_ skin: OverlaySkin) -> Bool {
        guard BubbleSkinCatalog.isClaudeCodeSkinAvailable(skin, ownedSkinIDs: ownedBubbleSkinIDs) else {
            return false
        }
        claudeCodeBubbleSkin = skin
        return true
    }

    @discardableResult
    public mutating func selectClaudeCodeFrameSkin(_ frame: FrameSkin) -> Bool {
        guard FrameCatalog.isClaudeCodeFrameAvailable(frame, ownedFrameSkinIDs: ownedFrameSkinIDs) else {
            return false
        }
        claudeCodeFrameSkin = frame
        return true
    }

    @discardableResult
    public mutating func selectSound(_ sound: SoundID) -> Bool {
        guard SoundCatalog.isSoundAvailable(sound, ownedSoundIDs: ownedSoundIDs) else {
            return false
        }
        selectedSoundID = sound.rawValue
        return true
    }

    public mutating func markAnimationOwned(_ animationID: String) {
        ownedAnimationIDs.insert(animationID)
    }

    public mutating func markBubbleSkinOwned(_ skinID: String) {
        ownedBubbleSkinIDs.insert(skinID)
    }

    public mutating func markFrameSkinOwned(_ frameSkinID: String) {
        ownedFrameSkinIDs.insert(frameSkinID)
    }

    public mutating func markSoundOwned(_ soundID: String) {
        ownedSoundIDs.insert(soundID)
    }

    public mutating func setOverlayScale(_ scale: Double) {
        overlayScale = Self.clampedOverlayScale(scale)
    }

    public static func clampedOverlayScale(_ scale: Double) -> Double {
        guard scale.isFinite else { return 1.0 }
        return min(max(scale, minimumOverlayScale), maximumOverlayScale)
    }

    private enum CodingKeys: String, CodingKey {
        case globalEnabled
        case animationEnabled
        case soundEnabled
        case overlayScale
        case claudeCodeAnimation
        case claudeCodeBubbleSkin
        case claudeCodeFrameSkin
        case ownedAnimationIDs
        case ownedBubbleSkinIDs
        case ownedFrameSkinIDs
        case ownedSoundIDs
        case selectedSoundID
        case claudeCodeTemplateID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let globalEnabled = try container.decodeIfPresent(Bool.self, forKey: .globalEnabled) ?? true
        let animationEnabled = try container.decodeIfPresent(Bool.self, forKey: .animationEnabled) ?? true
        let soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        let overlayScale = try container.decodeIfPresent(Double.self, forKey: .overlayScale) ?? 1.0
        let ownedAnimationIDs = try container.decodeIfPresent(Set<String>.self, forKey: .ownedAnimationIDs) ?? []
        let ownedBubbleSkinIDs = try container.decodeIfPresent(Set<String>.self, forKey: .ownedBubbleSkinIDs) ?? []
        let ownedFrameSkinIDs = try container.decodeIfPresent(Set<String>.self, forKey: .ownedFrameSkinIDs) ?? []
        let ownedSoundIDs = try container.decodeIfPresent(Set<String>.self, forKey: .ownedSoundIDs) ?? []
        let selectedSoundID = try container.decodeIfPresent(String.self, forKey: .selectedSoundID)
        let templateID = try container.decodeIfPresent(String.self, forKey: .claudeCodeTemplateID)
        let legacySelection = templateID.flatMap(LegacyTemplateMigration.claudeCodeSelection(templateID:))
        let decodedAnimation = try container.decodeIfPresent(ClaudeCodeAnimation.self, forKey: .claudeCodeAnimation)
            ?? .rightHandWave
        let decodedBubbleSkin = try container.decodeIfPresent(OverlaySkin.self, forKey: .claudeCodeBubbleSkin)
            ?? .windowsXP
        let frameSkin = try container.decodeIfPresent(FrameSkin.self, forKey: .claudeCodeFrameSkin) ?? .panel
        let animation = legacySelection?.animation ?? decodedAnimation
        let bubbleSkin = legacySelection?.bubbleSkin ?? decodedBubbleSkin
        self.init(
            globalEnabled: globalEnabled,
            animationEnabled: animationEnabled,
            soundEnabled: soundEnabled,
            overlayScale: overlayScale,
            claudeCodeAnimation: animation,
            claudeCodeBubbleSkin: bubbleSkin,
            claudeCodeFrameSkin: frameSkin,
            ownedAnimationIDs: ownedAnimationIDs,
            ownedBubbleSkinIDs: ownedBubbleSkinIDs,
            ownedFrameSkinIDs: ownedFrameSkinIDs,
            ownedSoundIDs: ownedSoundIDs,
            selectedSoundID: selectedSoundID
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(globalEnabled, forKey: .globalEnabled)
        try container.encode(animationEnabled, forKey: .animationEnabled)
        try container.encode(soundEnabled, forKey: .soundEnabled)
        try container.encode(overlayScale, forKey: .overlayScale)
        try container.encode(claudeCodeAnimation, forKey: .claudeCodeAnimation)
        try container.encode(claudeCodeBubbleSkin, forKey: .claudeCodeBubbleSkin)
        try container.encode(claudeCodeFrameSkin, forKey: .claudeCodeFrameSkin)
        try container.encode(ownedAnimationIDs, forKey: .ownedAnimationIDs)
        try container.encode(ownedBubbleSkinIDs, forKey: .ownedBubbleSkinIDs)
        try container.encode(ownedFrameSkinIDs, forKey: .ownedFrameSkinIDs)
        try container.encode(ownedSoundIDs, forKey: .ownedSoundIDs)
        try container.encodeIfPresent(selectedSoundID, forKey: .selectedSoundID)
    }
}

public final class NotificationPreferencesStore {
    private let url: URL

    public init(url: URL = ApplicationPaths.preferencesURL) {
        self.url = url
    }

    public func load() -> NotificationPreferences {
        guard let data = try? Data(contentsOf: url),
              let preferences = try? JSONDecoder.clinotify.decode(NotificationPreferences.self, from: data) else {
            return .defaultValue
        }
        return preferences
    }

    @discardableResult
    public func update(_ transform: (inout NotificationPreferences) -> Void) throws -> NotificationPreferences {
        var preferences = load()
        transform(&preferences)
        try save(preferences)
        return preferences
    }

    public func save(_ preferences: NotificationPreferences) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.clinotify.encode(preferences)
        try data.write(to: url, options: [.atomic])
    }
}
