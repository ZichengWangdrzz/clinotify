import AppKit
import CLINotifyShared

/// Authentic pixel-art rendering of the Claude crab mascot. Everything is drawn on a single fixed
/// logical grid (`gridColumns` x `gridRows`) so every art-pixel is the same crisp square. Animation
/// is frame-based: limbs are stamped at integer grid positions that change per frame, so there is no
/// sub-pixel motion (no shimmer) and no shape-swapping (no snap / volume change).
public enum ClaudeCrabArt {
    public static let gridColumns = 26
    public static let gridRows = 16

    // The body sprite is drawn shifted right so there are 5 clear columns on the left for the arm.
    private static let bodyColumn = 3

    private static let palette = PixelPalette([
        "r": NSColor(calibratedRed: 0.91, green: 0.46, blue: 0.24, alpha: 1),   // Claude orange body
        "d": NSColor(calibratedRed: 0.76, green: 0.35, blue: 0.17, alpha: 1),   // darker arm/shade
        "e": NSColor(calibratedRed: 0.10, green: 0.08, blue: 0.08, alpha: 1)    // eyes (black)
    ])

    // Flat terracotta rounded body with two black square eyes (matching the Claude mascot). The top
    // three rows are clear so a raised arm can show above the body. Legs and the arm are stamped.
    private static let body = PixelSprite([
        "....................",
        "....................",
        "....................",
        "....rrrrrrrrrr......",
        "..rrrrrrrrrrrrrr....",
        "..rrrrrrrrrrrrrr....",
        "..rrreerrrreerrr....",
        "..rrreerrrreerrr....",
        "..rrrrrrrrrrrrrr....",
        "..rrrrrrrrrrrrrr....",
        "..rrrrrrrrrrrrrr....",
        "..rrrrrrrrrrrrrr....",
        "...rrrrrrrrrrrr.....",
        "....................",
        "....................",
        "...................."
    ])

    // Repaints the eye band to a happy one-row squint (opaque over the open eyes underneath).
    private static let squintEyes = PixelSprite([
        "rrrrrrrr",
        "ee....ee"
    ])
    private static let squintEyesColumn = 8
    private static let squintEyesRow = 6

    // Raised waving arm: a diagonal forearm whose base sits at the body's right edge at mid-height
    // (rows 7-8), so its body junction mirrors the left arm's left-edge junction. The three poses
    // share the same filled-pixel count; only the hand (top two rows) shifts left/center/right while
    // the forearm stays put — the original wave motion, just re-rooted lower on the body.
    private static let armUp = PixelSprite([
        "...ddd.",
        "...ddd.",
        "...dd..",
        "..dd...",
        "ddd....",
        "dd....."
    ])
    private static let armLeft = PixelSprite([
        "..ddd..",
        "..ddd..",
        "...dd..",
        "..dd...",
        "ddd....",
        "dd....."
    ])
    private static let armRight = PixelSprite([
        "....ddd",
        "....ddd",
        "...dd..",
        "..dd...",
        "ddd....",
        "dd....."
    ])
    private static let armColumn = 19
    private static let armRow = 3

    // Static left arm: a 2-tall, 3-long block reaching horizontally out from the vertical center of
    // the body's left edge (col 5, rows 4-11 -> centered on rows 7-8). Right hand keeps its wave.
    private static let leftArm = PixelSprite([
        "ddd",
        "ddd"
    ])
    private static let leftArmColumn = 2
    private static let leftArmRow = 7

    // A single stubby leg; stamped at four x positions, lifted per frame for the squint leg-wave.
    private static let leg = PixelSprite([
        "rr",
        "rr"
    ])
    // Centered so the leftmost/rightmost legs align with the body's bottom corners (cols 6 and 17),
    // leaving no lone body pixel sticking out at the bottom-right.
    private static let legColumns = [6, 9, 13, 16]
    private static let legRow = 13

    /// Render the mascot for the given animation/progress into `rect`.
    public static func draw(
        in rect: NSRect,
        animation: ClaudeCodeAnimation,
        eventType: EventType,
        progress: Double,
        backingScale: CGFloat
    ) {
        let canvas = PixelCanvas(rect: rect, columns: gridColumns, rows: gridRows, backingScale: backingScale)
        let frame = Int((progress.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 4) % 4

        PixelArtContext.crisp {
            switch animation {
            case .rightHandWave:
                canvas.draw(body, column: bodyColumn, row: 0, palette: palette)
                drawRestingLegs(on: canvas)
                canvas.draw(leftArm, column: leftArmColumn, row: leftArmRow, palette: palette)
                let pose: PixelSprite
                switch frame {
                case 1: pose = armRight
                case 3: pose = armLeft
                default: pose = armUp
                }
                canvas.draw(pose, column: armColumn, row: armRow, palette: palette)
            case .squintLegWave:
                canvas.draw(body, column: bodyColumn, row: 0, palette: palette)
                canvas.draw(squintEyes, column: squintEyesColumn, row: squintEyesRow, palette: palette)
                drawWavingLegs(on: canvas, frame: frame)
            }
        }
    }

    private static func drawRestingLegs(on canvas: PixelCanvas) {
        for column in legColumns {
            canvas.draw(leg, column: column, row: legRow, palette: palette)
        }
    }

    private static func drawWavingLegs(on canvas: PixelCanvas, frame: Int) {
        // One leg lifts per frame, rippling left-to-right.
        for (index, column) in legColumns.enumerated() {
            let lift = index == frame ? 1 : 0
            canvas.draw(leg, column: column, row: legRow - lift, palette: palette)
        }
    }
}
