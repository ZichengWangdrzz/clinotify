import Foundation

/// Selectable notification sounds. Free entries map to built-in macOS system sounds; paid entries
/// are reserved for purchasable sound packs and gated by ownership exactly like animations/skins.
public enum SoundID: String, Codable, CaseIterable, Sendable {
    case glass = "glass"
    case ping = "ping"
    case submarine = "submarine"
    case arcadeChime = "arcade-chime"

    public var title: String {
        switch self {
        case .glass: return "Glass"
        case .ping: return "Ping"
        case .submarine: return "Submarine"
        case .arcadeChime: return "Arcade Chime"
        }
    }

    /// The macOS system sound name used to play this entry. Paid packs would ship bundled audio
    /// files; until then a system sound stands in so the reserved seam is fully wired.
    public var systemSoundName: String {
        switch self {
        case .glass: return "Glass"
        case .ping: return "Ping"
        case .submarine: return "Submarine"
        case .arcadeChime: return "Hero"
        }
    }
}

public enum SoundCatalog {
    public static let claudeCodeEntries: [CatalogEntry<SoundID>] = [
        CatalogEntry(id: .glass, title: "Glass", summary: "Soft glass chime.", access: .free),
        CatalogEntry(id: .ping, title: "Ping", summary: "Short ping.", access: .free),
        CatalogEntry(id: .submarine, title: "Submarine", summary: "Low submarine ping.", access: .free),
        CatalogEntry(id: .arcadeChime, title: "Arcade Chime", summary: "Retro arcade chime pack.", access: .paid)
    ]

    public static func claudeCodeEntry(_ sound: SoundID) -> CatalogEntry<SoundID>? {
        claudeCodeEntries.first { $0.id == sound }
    }

    public static func isSoundAvailable(_ sound: SoundID, ownedSoundIDs: Set<String>) -> Bool {
        guard let entry = claudeCodeEntry(sound) else { return false }
        return entry.access == .free || ownedSoundIDs.contains(sound.rawValue)
    }

    public static func availableSounds(ownedSoundIDs: Set<String>) -> [CatalogEntry<SoundID>] {
        claudeCodeEntries.filter { entry in
            entry.access == .free || ownedSoundIDs.contains(entry.id.rawValue)
        }
    }

    public static func defaultSound(ownedSoundIDs: Set<String>) -> SoundID {
        availableSounds(ownedSoundIDs: ownedSoundIDs).first?.id ?? .glass
    }
}
