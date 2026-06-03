import AppKit

/// Maps single characters in a sprite's rows to fill colors. Any character with no entry
/// (conventionally `.`) is treated as transparent and skipped.
public struct PixelPalette: Sendable {
    private let map: [Character: NSColor]

    public init(_ map: [Character: NSColor]) {
        self.map = map
    }

    public func color(for character: Character) -> NSColor? {
        map[character]
    }
}

/// A sprite authored as rows of characters (one character per art-pixel). Row 0 is the top row.
public struct PixelSprite: Sendable {
    public let rows: [String]
    public let width: Int
    public let height: Int

    public init(_ rows: [String]) {
        self.rows = rows
        self.height = rows.count
        self.width = rows.map(\.count).max() ?? 0
    }
}

/// Renders art-pixels as uniform, crisp, device-pixel-snapped squares into the current graphics
/// context. This is what gives the chunky, antialiasing-free pixel-art look: one logical grid,
/// every cell the same size, every edge snapped to the backing store.
public struct PixelCanvas {
    public let columns: Int
    public let rows: Int
    private let cell: CGFloat
    private let originX: CGFloat
    private let topY: CGFloat
    private let scale: CGFloat

    /// - Parameters:
    ///   - rect: destination rectangle in view points.
    ///   - columns/rows: logical grid resolution (the art-pixel count).
    ///   - backingScale: window backing scale, so cell edges land on device pixels.
    public init(rect: NSRect, columns: Int, rows: Int, backingScale: CGFloat) {
        self.columns = columns
        self.rows = rows
        self.scale = max(backingScale, 1)
        let rawCell = min(rect.width / CGFloat(columns), rect.height / CGFloat(rows))
        // Snap the cell size to whole device pixels so every cell is identical on screen.
        let snappedCell = max((rawCell * scale).rounded(.down) / scale, 1 / scale)
        self.cell = snappedCell
        let gridWidth = snappedCell * CGFloat(columns)
        let gridHeight = snappedCell * CGFloat(rows)
        self.originX = rect.minX + ((rect.width - gridWidth) / 2)
        self.topY = rect.maxY - ((rect.height - gridHeight) / 2)
    }

    private func snap(_ value: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }

    /// Fill a single grid cell. `row` 0 is the top row; y decreases as row increases.
    public func fill(column: Int, row: Int, color: NSColor) {
        let left = snap(originX + CGFloat(column) * cell)
        let right = snap(originX + CGFloat(column + 1) * cell)
        let top = snap(topY - CGFloat(row) * cell)
        let bottom = snap(topY - CGFloat(row + 1) * cell)
        color.setFill()
        NSRect(x: left, y: bottom, width: right - left, height: top - bottom).fill()
    }

    /// Stamp a sprite with its top-left art-pixel at (column, row).
    public func draw(_ sprite: PixelSprite, column: Int, row: Int, palette: PixelPalette) {
        for (rowOffset, line) in sprite.rows.enumerated() {
            for (columnOffset, character) in line.enumerated() {
                guard let color = palette.color(for: character) else { continue }
                fill(column: column + columnOffset, row: row + rowOffset, color: color)
            }
        }
    }
}

public enum PixelArtContext {
    /// Runs `body` with antialiasing disabled and interpolation off, restoring state afterward.
    /// All pixel-art drawing must happen inside this so squares stay crisp.
    public static func crisp(_ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.shouldAntialias = false
        NSGraphicsContext.current?.imageInterpolation = .none
        body()
        NSGraphicsContext.restoreGraphicsState()
    }
}
