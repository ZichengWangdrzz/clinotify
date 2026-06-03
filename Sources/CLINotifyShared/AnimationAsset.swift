import Foundation

public struct AnimationAsset: Equatable, Sendable {
    public enum Renderer: String, Sendable {
        case claudePixelRightHandWave
        case claudePixelSquintLegWave
        case fallback
    }

    public var resourceName: String
    public var lottieFilename: String
    public var bundledFilename: String?
    public var renderer: Renderer
    public var loop: Bool
    public var duration: TimeInterval
    public var displayDuration: TimeInterval
    public var frameRate: Double

    public init(
        resourceName: String,
        lottieFilename: String,
        bundledFilename: String? = nil,
        renderer: Renderer = .fallback,
        loop: Bool,
        duration: TimeInterval,
        displayDuration: TimeInterval? = nil,
        frameRate: Double = 60
    ) {
        self.resourceName = resourceName
        self.lottieFilename = lottieFilename
        self.bundledFilename = bundledFilename
        self.renderer = renderer
        self.loop = loop
        self.duration = duration
        self.displayDuration = displayDuration ?? duration
        self.frameRate = frameRate
    }

    public static func claudeCode(_ animation: ClaudeCodeAnimation) -> AnimationAsset {
        switch animation {
        case .rightHandWave:
            return AnimationAsset(
                resourceName: "claude_code_right_hand_wave",
                lottieFilename: "claude_code_right_hand_wave.lottie",
                bundledFilename: "Claude-Pixel-Right-Hand-Wave-120fps.mp4",
                renderer: .claudePixelRightHandWave,
                loop: true,
                duration: 2.0,
                displayDuration: 8.0,
                frameRate: 120
            )
        case .squintLegWave:
            return AnimationAsset(
                resourceName: "claude_code_squint_leg_wave",
                lottieFilename: "claude_code_squint_leg_wave.lottie",
                bundledFilename: "Claude-Pixel-Squint-Leg-Wave-120fps.mp4",
                renderer: .claudePixelSquintLegWave,
                loop: true,
                duration: 2.0,
                displayDuration: 8.0,
                frameRate: 120
            )
        }
    }

    public static func asset(
        source: EventSource,
        type: EventType,
        preferences: NotificationPreferences = .defaultValue
    ) -> AnimationAsset {
        switch source {
        case .claudeCode:
            return claudeCode(preferences.claudeCodeAnimation)
        case .codex:
            switch type {
            case .done:
                return AnimationAsset(resourceName: "codex_done", lottieFilename: "codex_done.lottie", loop: false, duration: 1.4)
            case .attention:
                return AnimationAsset(resourceName: "codex_attention", lottieFilename: "codex_attention.lottie", loop: true, duration: 4.0)
            }
        }
    }
}
