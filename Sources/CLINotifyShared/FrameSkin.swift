import CoreGraphics
import Foundation

/// The frame axis: a visible panel that wraps the toast content (mascot + bubble). Mirrors the
/// other skin axes (animation / bubble / sound): an enum + a `Catalog` of `CatalogEntry<ID>` gated
/// purely by ownership, defaults FREE. `.panel` is the visible rounded card (default); `.none`
/// draws nothing.
public enum FrameSkin: String, Codable, CaseIterable, Sendable {
    case panel
    case none

    public var title: String {
        switch self {
        case .panel:
            return "Panel"
        case .none:
            return "None"
        }
    }

    /// The concrete drawing recipe for this frame skin. Kept AppKit-free (plain RGBA Doubles) so
    /// CLINotifyShared has no AppKit dependency; the AppKit side converts the components to NSColor.
    public var style: FrameStyle {
        switch self {
        case .panel:
            return .panel
        case .none:
            return .none
        }
    }
}

/// An RGBA color expressed as plain `Double` components in 0...1. CLINotifyShared stays AppKit-free,
/// so the AppKit side converts this into `NSColor(calibratedRed:green:blue:alpha:)`.
public struct FrameColor: Sendable, Equatable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// A fully transparent color (no visible draw).
    public static let clear = FrameColor(r: 0, g: 0, b: 0, a: 0)
}

/// How to draw the frame panel behind the toast content.
public struct FrameStyle: Sendable, Equatable {
    public var cornerRadius: CGFloat
    public var fillColor: FrameColor
    public var strokeColor: FrameColor
    public var strokeWidth: CGFloat
    public var hasShadow: Bool
    /// Extra interior padding applied inside the frame, beyond the content's own layout margin.
    public var contentInset: CGFloat

    public init(
        cornerRadius: CGFloat,
        fillColor: FrameColor,
        strokeColor: FrameColor,
        strokeWidth: CGFloat,
        hasShadow: Bool,
        contentInset: CGFloat
    ) {
        self.cornerRadius = cornerRadius
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.hasShadow = hasShadow
        self.contentInset = contentInset
    }

    /// No frame: fully transparent, nothing drawn.
    public static let none = FrameStyle(
        cornerRadius: 0,
        fillColor: .clear,
        strokeColor: .clear,
        strokeWidth: 0,
        hasShadow: false,
        contentInset: 0
    )

    /// A light rounded card: near-white fill, a subtle gray 1pt border, soft shadow, gentle inset.
    public static let panel = FrameStyle(
        cornerRadius: 14,
        fillColor: FrameColor(r: 0.97, g: 0.97, b: 0.97, a: 0.97),
        strokeColor: FrameColor(r: 0.78, g: 0.78, b: 0.78, a: 1),
        strokeWidth: 1,
        hasShadow: true,
        contentInset: 6
    )
}

public enum FrameCatalog {
    public static let claudeCodeEntries: [CatalogEntry<FrameSkin>] = [
        CatalogEntry(
            id: .panel,
            title: "Panel",
            summary: "Light rounded card with a soft shadow behind the content.",
            access: .free
        ),
        CatalogEntry(
            id: .none,
            title: "None",
            summary: "No frame; the mascot and bubble float on the desktop.",
            access: .free
        )
    ]

    public static func claudeCodeEntry(_ frame: FrameSkin) -> CatalogEntry<FrameSkin>? {
        claudeCodeEntries.first { $0.id == frame }
    }

    public static func isClaudeCodeFrameAvailable(_ frame: FrameSkin, ownedFrameSkinIDs: Set<String>) -> Bool {
        guard let entry = claudeCodeEntry(frame) else { return false }
        return entry.access == .free || ownedFrameSkinIDs.contains(frame.rawValue)
    }

    public static func availableClaudeCodeFrames(ownedFrameSkinIDs: Set<String>) -> [CatalogEntry<FrameSkin>] {
        claudeCodeEntries.filter { entry in
            entry.access == .free || ownedFrameSkinIDs.contains(entry.id.rawValue)
        }
    }

    public static func defaultClaudeCodeFrame(ownedFrameSkinIDs: Set<String>) -> FrameSkin {
        availableClaudeCodeFrames(ownedFrameSkinIDs: ownedFrameSkinIDs).first?.id ?? .panel
    }

    public static func selectedSkin(for source: EventSource, preferences: NotificationPreferences) -> FrameSkin {
        switch source {
        case .claudeCode:
            return preferences.claudeCodeFrameSkin
        case .codex:
            return .panel
        }
    }
}
