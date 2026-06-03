import AppKit
import CLINotifyPixelArt
import CLINotifyShared
import Foundation

// Offscreen renderer used only for design iteration: dumps the pixel-art mascot frames and the XP
// bubble to PNGs so they can be inspected without launching the menu-bar overlay.

let outputDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    : URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("pixelpreview")
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

func render(size: NSSize, scale: CGFloat, _ draw: (NSRect) -> Void) -> Data? {
    let pixelW = Int(size.width * scale)
    let pixelH = Int(size.height * scale)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelW,
        pixelsHigh: pixelH,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    rep.size = size
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    // Checkerboard background so transparency is visible.
    let rect = NSRect(origin: .zero, size: size)
    NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
    rect.fill()
    draw(rect)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

func write(_ data: Data?, _ name: String) {
    guard let data else { print("FAILED \(name)"); return }
    let url = outputDir.appendingPathComponent(name)
    try? data.write(to: url)
    print(url.path)
}

let scale: CGFloat = 4
let mascotSize = NSSize(width: 110, height: 90)

for frame in 0..<4 {
    let progress = Double(frame) / 4.0
    write(render(size: mascotSize, scale: scale) { rect in
        ClaudeCrabArt.draw(in: rect, animation: .rightHandWave, eventType: .done, progress: progress, backingScale: scale)
    }, "wave-\(frame).png")
    write(render(size: mascotSize, scale: scale) { rect in
        ClaudeCrabArt.draw(in: rect, animation: .squintLegWave, eventType: .attention, progress: progress, backingScale: scale)
    }, "squint-\(frame).png")
}

write(render(size: NSSize(width: 200, height: 80), scale: scale) { rect in
    XPBubbleArt.drawSpeechBubble(in: rect, backingScale: scale)
}, "bubble.png")

write(render(size: NSSize(width: 90, height: 40), scale: scale) { rect in
    XPBubbleArt.drawButton(in: rect, backingScale: scale)
}, "button.png")

// Auto-sizing check: bubble width follows the (user-set) label, mirroring OverlayWindow.baseLayout
// (grow to fit; only shrink the font once past the max width).
func bubbleFit(for text: String) -> (width: CGFloat, fontSize: CGFloat) {
    let maxTextWidth: CGFloat = 230
    var fontSize: CGFloat = 18
    func measure(_ s: CGFloat) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: s, weight: .bold)]).width
    }
    var w = measure(fontSize)
    while w > maxTextWidth, fontSize > 11 { fontSize -= 1; w = measure(fontSize) }
    let breathingRoom: CGFloat = 16
    return (min(max(w + 22 + 14 + breathingRoom, 74), maxTextWidth + 36 + breathingRoom), fontSize)
}
func renderLabeledBubble(_ text: String, _ name: String) {
    let bubbleH: CGFloat = 40
    let fit = bubbleFit(for: text)
    write(render(size: NSSize(width: fit.width + 8, height: bubbleH + 8), scale: scale) { rect in
        let bubble = NSRect(x: 4, y: 4, width: fit.width, height: bubbleH)
        XPBubbleArt.drawSpeechBubble(in: bubble, backingScale: scale)
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fit.fontSize, weight: .bold),
            .foregroundColor: NSColor(calibratedRed: 0.04, green: 0.12, blue: 0.38, alpha: 1),
            .paragraphStyle: paragraph
        ]
        let inset = NSRect(x: bubble.minX + 22, y: bubble.minY, width: bubble.width - 36, height: bubble.height)
        let ts = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(in: NSRect(x: inset.minX, y: inset.midY - ts.height / 2, width: inset.width, height: ts.height), withAttributes: attrs)
    }, name)
}
renderLabeledBubble("Hi", "bubble-short.png")
renderLabeledBubble("Manual Test", "bubble-mid.png")
renderLabeledBubble("my-very-long-session-name", "bubble-long.png")
renderLabeledBubble("mannual mannual test", "bubble-mannual.png")

print("done -> \(outputDir.path)")
