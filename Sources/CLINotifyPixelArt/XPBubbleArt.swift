import AppKit

/// Chunky pixel-art Windows-XP speech balloon and OK button. Both are drawn on a pixel grid derived
/// from the destination rect so the bevels, outline and tail are made of uniform crisp blocks — the
/// caller draws the (monospace) text on top.
public enum XPBubbleArt {
    private enum Blue {
        static let outline = NSColor(calibratedRed: 0.10, green: 0.24, blue: 0.53, alpha: 1)
        static let top = NSColor(calibratedRed: 0.88, green: 0.94, blue: 1.00, alpha: 1)
        static let mid = NSColor(calibratedRed: 0.69, green: 0.83, blue: 1.00, alpha: 1)
        static let bottom = NSColor(calibratedRed: 0.50, green: 0.70, blue: 0.97, alpha: 1)
        static let bevelLight = NSColor(calibratedRed: 0.98, green: 0.99, blue: 1.00, alpha: 1)
        static let bevelShadow = NSColor(calibratedRed: 0.33, green: 0.51, blue: 0.83, alpha: 1)
    }

    private enum Green {
        static let outline = NSColor(calibratedRed: 0.13, green: 0.36, blue: 0.09, alpha: 1)
        static let top = NSColor(calibratedRed: 0.78, green: 0.93, blue: 0.58, alpha: 1)
        static let mid = NSColor(calibratedRed: 0.55, green: 0.81, blue: 0.36, alpha: 1)
        static let bottom = NSColor(calibratedRed: 0.36, green: 0.64, blue: 0.21, alpha: 1)
        static let bevelLight = NSColor(calibratedRed: 0.90, green: 0.98, blue: 0.74, alpha: 1)
        static let bevelShadow = NSColor(calibratedRed: 0.27, green: 0.52, blue: 0.15, alpha: 1)
    }

    /// Speech balloon with a stepped pixel tail on the left edge (pointing at the mascot).
    public static func drawSpeechBubble(in rect: NSRect, backingScale: CGFloat) {
        let rows = max(Int((rect.height / (rect.height / 13)).rounded()), 12)
        let unit = rect.height / CGFloat(rows)
        let columns = max(Int((rect.width / unit).rounded()), 12)
        let canvas = PixelCanvas(rect: rect, columns: columns, rows: rows, backingScale: backingScale)

        // Tail size is derived from the height (not width) so it stays a small, roughly constant
        // pointer; a width-proportional tail would balloon on wide bubbles and push the body past the
        // caller's fixed text inset, making the label collide with the border.
        let tailWidth = max(rows / 4, 2)              // tail steps out to the left
        let bodyLeft = tailWidth
        let lastCol = columns - 1
        let lastRow = rows - 1

        PixelArtContext.crisp {
            for row in 0..<rows {
                for column in bodyLeft...lastCol {
                    // Cut the four corners by one pixel for a rounded-pixel silhouette.
                    let onLeft = column == bodyLeft
                    let onRight = column == lastCol
                    let onTop = row == 0
                    let onBottom = row == lastRow
                    if (onTop || onBottom) && (onLeft || onRight) { continue }

                    let color: NSColor
                    if onTop || onBottom || onLeft || onRight {
                        color = Blue.outline
                    } else if row == 1 || column == bodyLeft + 1 {
                        color = Blue.bevelLight
                    } else if row == lastRow - 1 || column == lastCol - 1 {
                        color = Blue.bevelShadow
                    } else {
                        color = bandColor(row: row, rows: rows, top: Blue.top, mid: Blue.mid, bottom: Blue.bottom)
                    }
                    canvas.fill(column: column, row: row, color: color)
                }
            }

            // Stepped pixel tail centered vertically on the left.
            let midRow = rows / 2
            for step in 0..<tailWidth {
                let column = bodyLeft - 1 - step
                guard column >= 0 else { break }
                let half = step + 1
                for row in (midRow - half)...(midRow + half) {
                    let color = (row == midRow - half || row == midRow + half) ? Blue.outline : Blue.mid
                    canvas.fill(column: column, row: row, color: color)
                }
            }
        }
    }

    /// Glossy green pixel OK button (text drawn by the caller).
    public static func drawButton(in rect: NSRect, backingScale: CGFloat) {
        let rows = max(Int((rect.height / (rect.height / 8)).rounded()), 7)
        let unit = rect.height / CGFloat(rows)
        let columns = max(Int((rect.width / unit).rounded()), 7)
        let canvas = PixelCanvas(rect: rect, columns: columns, rows: rows, backingScale: backingScale)
        let lastCol = columns - 1
        let lastRow = rows - 1

        PixelArtContext.crisp {
            for row in 0..<rows {
                for column in 0..<columns {
                    let onLeft = column == 0
                    let onRight = column == lastCol
                    let onTop = row == 0
                    let onBottom = row == lastRow
                    if (onTop || onBottom) && (onLeft || onRight) { continue }

                    let color: NSColor
                    if onTop || onBottom || onLeft || onRight {
                        color = Green.outline
                    } else if row == 1 || column == 1 {
                        color = Green.bevelLight
                    } else if row == lastRow - 1 || column == lastCol - 1 {
                        color = Green.bevelShadow
                    } else {
                        color = bandColor(row: row, rows: rows, top: Green.top, mid: Green.mid, bottom: Green.bottom)
                    }
                    canvas.fill(column: column, row: row, color: color)
                }
            }
        }
    }

    private static func bandColor(row: Int, rows: Int, top: NSColor, mid: NSColor, bottom: NSColor) -> NSColor {
        let fraction = Double(row) / Double(max(rows - 1, 1))
        if fraction < 0.38 { return top }
        if fraction < 0.68 { return mid }
        return bottom
    }
}
