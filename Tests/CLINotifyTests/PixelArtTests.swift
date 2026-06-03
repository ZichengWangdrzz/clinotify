import AppKit
import XCTest
@testable import CLINotifyPixelArt
import CLINotifyShared

final class PixelArtTests: XCTestCase {
    func testPixelSpriteReportsDimensions() {
        let sprite = PixelSprite([
            "....",
            "kk..",
            "kkkk"
        ])
        XCTAssertEqual(sprite.height, 3)
        XCTAssertEqual(sprite.width, 4)
    }

    func testPaletteSkipsUnknownCharacters() {
        let palette = PixelPalette(["r": .red])
        XCTAssertEqual(palette.color(for: "r"), .red)
        XCTAssertNil(palette.color(for: "."))
        XCTAssertNil(palette.color(for: "x"))
    }

    func testCrabDrawsOpaqueBodyAndTransparentCorner() throws {
        let size = NSSize(width: 88, height: 72)
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let ctx = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ClaudeCrabArt.draw(
            in: NSRect(origin: .zero, size: size),
            animation: .rightHandWave,
            eventType: .done,
            progress: 0,
            backingScale: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        // The body center should be painted; the very top-left corner should stay transparent.
        let center = try XCTUnwrap(rep.colorAt(x: Int(size.width / 2), y: Int(size.height / 2)))
        XCTAssertGreaterThan(center.alphaComponent, 0.5)
        let corner = try XCTUnwrap(rep.colorAt(x: 1, y: 1))
        XCTAssertLessThan(corner.alphaComponent, 0.5)
    }
}
