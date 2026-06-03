import Foundation

/// Per-terminal (per-TTY) preference override.
///
/// Every field is optional: `nil` means "inherit the global value". The same value type is both
/// the per-terminal mute switch and the reserved surface for per-terminal animation/skin/sound
/// swaps. Merging and resolution are pure so they are trivially `Sendable` and testable.
public struct SessionPreferenceOverride: Codable, Equatable, Sendable {
    public var soundMuted: Bool?
    public var animationEnabled: Bool?
    public var claudeCodeAnimation: ClaudeCodeAnimation?
    public var claudeCodeBubbleSkin: OverlaySkin?
    public var claudeCodeFrameSkin: FrameSkin?
    public var selectedSoundID: String?

    public init(
        soundMuted: Bool? = nil,
        animationEnabled: Bool? = nil,
        claudeCodeAnimation: ClaudeCodeAnimation? = nil,
        claudeCodeBubbleSkin: OverlaySkin? = nil,
        claudeCodeFrameSkin: FrameSkin? = nil,
        selectedSoundID: String? = nil
    ) {
        self.soundMuted = soundMuted
        self.animationEnabled = animationEnabled
        self.claudeCodeAnimation = claudeCodeAnimation
        self.claudeCodeBubbleSkin = claudeCodeBubbleSkin
        self.claudeCodeFrameSkin = claudeCodeFrameSkin
        self.selectedSoundID = selectedSoundID
    }

    /// True when no field is set, i.e. the override is a no-op and can be pruned from storage.
    public var isEmpty: Bool {
        soundMuted == nil
            && animationEnabled == nil
            && claudeCodeAnimation == nil
            && claudeCodeBubbleSkin == nil
            && claudeCodeFrameSkin == nil
            && selectedSoundID == nil
    }

    /// Return a new override where `other`'s set fields win over `self`'s; unset fields fall back.
    public func merging(_ other: SessionPreferenceOverride) -> SessionPreferenceOverride {
        SessionPreferenceOverride(
            soundMuted: other.soundMuted ?? soundMuted,
            animationEnabled: other.animationEnabled ?? animationEnabled,
            claudeCodeAnimation: other.claudeCodeAnimation ?? claudeCodeAnimation,
            claudeCodeBubbleSkin: other.claudeCodeBubbleSkin ?? claudeCodeBubbleSkin,
            claudeCodeFrameSkin: other.claudeCodeFrameSkin ?? claudeCodeFrameSkin,
            selectedSoundID: other.selectedSoundID ?? selectedSoundID
        )
    }

    /// Merge this override over `global`, returning a fresh value WITHOUT mutating `global`.
    ///
    /// Animation/skin selections still go through the catalog ownership gates, so a locked
    /// selection is silently ignored (the global value is kept) rather than applied.
    public func resolved(global: NotificationPreferences) -> NotificationPreferences {
        var resolved = global
        if let animationEnabled {
            resolved.animationEnabled = animationEnabled
        }
        if let soundMuted {
            resolved.soundEnabled = global.soundEnabled && !soundMuted
        }
        if let claudeCodeAnimation {
            resolved.selectClaudeCodeAnimation(claudeCodeAnimation)
        }
        if let claudeCodeBubbleSkin {
            resolved.selectClaudeCodeBubbleSkin(claudeCodeBubbleSkin)
        }
        if let claudeCodeFrameSkin {
            resolved.selectClaudeCodeFrameSkin(claudeCodeFrameSkin)
        }
        if let selectedSoundID, let sound = SoundID(rawValue: selectedSoundID) {
            resolved.selectSound(sound)
        }
        return resolved
    }
}
