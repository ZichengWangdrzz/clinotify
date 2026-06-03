import Foundation

public enum CatalogAccess: String, Codable, Sendable {
    case free
    case paid
}

public struct CatalogEntry<ID: RawRepresentable & Codable & Sendable & Equatable>: Codable, Equatable, Sendable
where ID.RawValue == String {
    public var id: ID
    public var title: String
    public var summary: String
    public var access: CatalogAccess

    public init(id: ID, title: String, summary: String, access: CatalogAccess) {
        self.id = id
        self.title = title
        self.summary = summary
        self.access = access
    }
}

public enum OverlaySkin: String, Codable, CaseIterable, Sendable {
    case windowsXP = "windows-xp"
    case classicPixel = "classic-pixel"

    public var title: String {
        switch self {
        case .windowsXP:
            return "Windows XP"
        case .classicPixel:
            return "Classic Pixel"
        }
    }
}

public enum AnimationCatalog {
    public static let claudeCodeEntries: [CatalogEntry<ClaudeCodeAnimation>] = [
        CatalogEntry(
            id: .rightHandWave,
            title: "Right hand wave",
            summary: "Claude pixel crab waves its right hand.",
            access: .free
        ),
        CatalogEntry(
            id: .squintLegWave,
            title: "Squint leg wave",
            summary: "Claude pixel crab squints and ripples its legs.",
            access: .free
        )
    ]

    public static func claudeCodeEntry(_ animation: ClaudeCodeAnimation) -> CatalogEntry<ClaudeCodeAnimation>? {
        claudeCodeEntries.first { $0.id == animation }
    }

    public static func isClaudeCodeAnimationAvailable(
        _ animation: ClaudeCodeAnimation,
        ownedAnimationIDs: Set<String>
    ) -> Bool {
        guard let entry = claudeCodeEntry(animation) else { return false }
        return entry.access == .free || ownedAnimationIDs.contains(animation.rawValue)
    }

    public static func availableClaudeCodeAnimations(ownedAnimationIDs: Set<String>) -> [CatalogEntry<ClaudeCodeAnimation>] {
        claudeCodeEntries.filter { entry in
            entry.access == .free || ownedAnimationIDs.contains(entry.id.rawValue)
        }
    }

    public static func defaultClaudeCodeAnimation(ownedAnimationIDs: Set<String>) -> ClaudeCodeAnimation {
        availableClaudeCodeAnimations(ownedAnimationIDs: ownedAnimationIDs).first?.id ?? .rightHandWave
    }
}

public enum BubbleSkinCatalog {
    public static let claudeCodeEntries: [CatalogEntry<OverlaySkin>] = [
        CatalogEntry(
            id: .windowsXP,
            title: "Windows XP",
            summary: "Blue beveled speech bubble with green OK button.",
            access: .free
        ),
        CatalogEntry(
            id: .classicPixel,
            title: "Classic Pixel",
            summary: "Flat white pixel speech bubble with green pixel OK button.",
            access: .paid
        )
    ]

    public static func claudeCodeEntry(_ skin: OverlaySkin) -> CatalogEntry<OverlaySkin>? {
        claudeCodeEntries.first { $0.id == skin }
    }

    public static func isClaudeCodeSkinAvailable(_ skin: OverlaySkin, ownedSkinIDs: Set<String>) -> Bool {
        guard let entry = claudeCodeEntry(skin) else { return false }
        return entry.access == .free || ownedSkinIDs.contains(skin.rawValue)
    }

    public static func availableClaudeCodeSkins(ownedSkinIDs: Set<String>) -> [CatalogEntry<OverlaySkin>] {
        claudeCodeEntries.filter { entry in
            entry.access == .free || ownedSkinIDs.contains(entry.id.rawValue)
        }
    }

    public static func defaultClaudeCodeSkin(ownedSkinIDs: Set<String>) -> OverlaySkin {
        availableClaudeCodeSkins(ownedSkinIDs: ownedSkinIDs).first?.id ?? .windowsXP
    }

    public static func selectedSkin(for source: EventSource, preferences: NotificationPreferences) -> OverlaySkin {
        switch source {
        case .claudeCode:
            return preferences.claudeCodeBubbleSkin
        case .codex:
            return .windowsXP
        }
    }
}

public enum LegacyTemplateMigration {
    public static func claudeCodeSelection(
        templateID: String
    ) -> (animation: ClaudeCodeAnimation, bubbleSkin: OverlaySkin)? {
        switch templateID {
        case "claude-code-xp-wave":
            return (.rightHandWave, .windowsXP)
        case "claude-code-xp-squint":
            return (.squintLegWave, .windowsXP)
        default:
            return nil
        }
    }
}
