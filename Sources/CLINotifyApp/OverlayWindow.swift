import AppKit
import CLINotifyPixelArt
import CLINotifyShared

/// Base-point (unscaled) layout of an overlay's pieces. The content size and the bubble width are
/// derived from the (user-set) session label so the bubble frame auto-fits the text.
struct OverlayBaseLayout {
    let size: NSSize
    let mascot: NSRect
    let bubble: NSRect
    let ok: NSRect
    let hasBubble: Bool
    let labelFontSize: CGFloat
}

final class OverlayWindow: NSWindow {
    static let mascotBaseSize = NSSize(width: 86, height: 78)
    /// Horizontal padding inside the bubble (base points): left clears the pixel tail/bevel.
    static let bubblePadLeft: CGFloat = 22
    static let bubblePadRight: CGFloat = 14

    /// Truncate the (user-set) label to a sane maximum before measuring/drawing.
    static func displayLabel(_ label: String?) -> String {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.count > 26 ? String(trimmed.prefix(26)) + "…" : trimmed
    }

    static func measureLabelWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// Compute the base-point layout for the given label. With no label, just the mascot centered;
    /// with a label, a left mascot plus a right column of an auto-sized bubble over the OK button.
    static func baseLayout(label: String?) -> OverlayBaseLayout {
        let margin: CGFloat = 16
        let mascot = mascotBaseSize
        let display = displayLabel(label)
        guard !display.isEmpty else {
            let size = NSSize(width: mascot.width + margin * 2, height: mascot.height + margin * 2)
            return OverlayBaseLayout(
                size: size,
                mascot: NSRect(x: margin, y: margin, width: mascot.width, height: mascot.height),
                bubble: .zero,
                ok: .zero,
                hasBubble: false,
                labelFontSize: 0
            )
        }

        // Grow the bubble to fit the label; only once it hits the max width do we shrink the font.
        let maxTextWidth: CGFloat = 230
        var fontSize: CGFloat = 18
        var textWidth = measureLabelWidth(display, fontSize: fontSize)
        while textWidth > maxTextWidth, fontSize > 11 {
            fontSize -= 1
            textWidth = measureLabelWidth(display, fontSize: fontSize)
        }
        let padLeft = bubblePadLeft
        let padRight = bubblePadRight
        // Extra slack beyond the raw text so the (centered) label keeps a margin on both sides
        // instead of butting against the balloon's bevel/outline.
        let breathingRoom: CGFloat = 16
        let bubbleW = min(
            max(textWidth + padLeft + padRight + breathingRoom, 74),
            maxTextWidth + padLeft + padRight + breathingRoom
        )
        let bubbleH: CGFloat = 40
        let okW: CGFloat = 52
        let okH: CGFloat = 22
        let gapBubbleOK: CGFloat = 8
        let gapMascotBubble: CGFloat = 6

        let rightColumnH = bubbleH + gapBubbleOK + okH
        let contentH = max(mascot.height, rightColumnH) + margin * 2
        let contentW = margin + mascot.width + gapMascotBubble + bubbleW + margin

        let mascotRect = NSRect(x: margin, y: (contentH - mascot.height) / 2, width: mascot.width, height: mascot.height)
        let bubbleX = margin + mascot.width + gapMascotBubble
        let bubbleY = contentH - margin - bubbleH
        let bubbleRect = NSRect(x: bubbleX, y: bubbleY, width: bubbleW, height: bubbleH)
        let okRect = NSRect(x: bubbleRect.midX - okW / 2, y: bubbleY - gapBubbleOK - okH, width: okW, height: okH)

        return OverlayBaseLayout(
            size: NSSize(width: contentW, height: contentH),
            mascot: mascotRect,
            bubble: bubbleRect,
            ok: okRect,
            hasBubble: true,
            labelFontSize: fontSize
        )
    }

    private var isDismissing = false
    private let onClosed: (OverlayWindow) -> Void
    private weak var animationView: OverlayContentView?

    // MARK: - Screen toast overlay

    init(
        event: AgentEvent,
        label: String?,
        screen: NSScreen,
        asset: AnimationAsset,
        bubbleSkin: OverlaySkin,
        frameStyle: FrameStyle,
        overlayScale: Double,
        stackIndex: Int,
        onClosed: @escaping (OverlayWindow) -> Void
    ) {
        self.onClosed = onClosed
        let visualScale = CGFloat(NotificationPreferences.clampedOverlayScale(overlayScale))
        let size = OverlayWindow.baseLayout(label: label).size.scaled(by: visualScale)
        let frame = OverlayWindow.frame(size: size, on: screen, stackIndex: stackIndex)
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // CRITICAL: programmatically-created NSWindows default isReleasedWhenClosed = true, which adds
        // an AppKit release on close() that ARC doesn't balance. OverlayManager already owns the window
        // (its `windows` dict) and frees it deterministically, so without this the close() in dismiss()
        // over-releases the window and the next CoreAnimation transaction drains a freed object
        // (segfault in objc_autoreleasePoolPop -> _Block_release during CA::commit). Let ARC own it.
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        hasShadow = false
        alphaValue = 0
        let content = OverlayContentView(
            event: event,
            label: label,
            asset: asset,
            bubbleSkin: bubbleSkin,
            frameStyle: frameStyle,
            overlayScale: visualScale,
            dismissOnAnyClick: false,
            onDismissRequested: { [weak self] in
                self?.dismiss()
            }
        )
        animationView = content
        contentView = content

        alphaValue = 1
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        // First keystroke breaks the overlay; it is consumed (no passthrough into the terminal).
        dismiss()
    }

    /// Dismiss by sliding the toast off the RIGHT edge of the screen while fading, then close. The
    /// manager removes it from the stack on completion and slides the toasts below it up.
    func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        animationView?.stopAnimation()
        // Push fully past the right edge: it sits one margin in from `visibleFrame.maxX`, so a shift of
        // its own width plus two margins clears the screen regardless of where it started.
        let offscreen = frame.offsetBy(dx: frame.width + 48, dy: 0)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().setFrame(offscreen, display: true)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.close()
            self.onClosed(self)
        })
    }

    /// Re-slot to a stack index. A dismissing toast is already sliding off-screen, so it ignores reflow.
    func move(toStackIndex stackIndex: Int, on screen: NSScreen, animated: Bool = false) {
        guard !isDismissing else { return }
        let newFrame = Self.frame(size: frame.size, on: screen, stackIndex: stackIndex)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().setFrame(newFrame, display: true)
            }
        } else {
            setFrame(newFrame, display: true, animate: false)
        }
    }

    private static func frame(size: NSSize, on screen: NSScreen, stackIndex: Int) -> NSRect {
        let visible = screen.visibleFrame
        let margin: CGFloat = 24
        let spacing: CGFloat = 10
        let proposedY = visible.maxY - size.height - margin - CGFloat(stackIndex) * (size.height + spacing)
        let y = max(visible.minY + margin, proposedY)
        return NSRect(
            x: visible.maxX - size.width - margin,
            y: y,
            width: size.width,
            height: size.height
        )
    }
}

final class OverlayContentView: NSView {
    private let event: AgentEvent
    private let label: String?
    private let asset: AnimationAsset
    private let bubbleSkin: OverlaySkin
    private let frameStyle: FrameStyle
    private let overlayScale: CGFloat
    private let dismissOnAnyClick: Bool
    private let onDismissRequested: () -> Void
    private let startedAt = Date()
    private var timer: Timer?

    init(
        event: AgentEvent,
        label: String?,
        asset: AnimationAsset,
        bubbleSkin: OverlaySkin,
        frameStyle: FrameStyle,
        overlayScale: CGFloat,
        dismissOnAnyClick: Bool = false,
        onDismissRequested: @escaping () -> Void
    ) {
        self.event = event
        self.label = label
        self.asset = asset
        self.bubbleSkin = bubbleSkin
        self.frameStyle = frameStyle
        self.overlayScale = overlayScale
        self.dismissOnAnyClick = dismissOnAnyClick
        self.onDismissRequested = onDismissRequested
        super.init(frame: .zero)
        wantsLayer = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / asset.frameRate, repeats: true) { [weak self] _ in
            self?.needsDisplay = true
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        timer?.invalidate()
    }

    /// Stop the animation loop immediately (used when the overlay is being dismissed).
    func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if dismissOnAnyClick || overlayLayout().okRect.contains(point) {
            onDismissRequested()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let elapsed = Date().timeIntervalSince(startedAt)
        let progress = asset.loop
            ? elapsed.truncatingRemainder(dividingBy: asset.duration) / asset.duration
            : min(elapsed / asset.duration, 1)
        let pulse = 1.0 + CGFloat(sin(progress * .pi * 2)) * (event.type == .attention ? 0.08 : 0.025)
        let accent = event.source == .claudeCode
            ? NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)
            : NSColor(calibratedWhite: 0.12, alpha: 1)
        let layout = overlayLayout()
        let hasBubble = layout.hasBubble
        let bubbleRect = layout.bubbleRect
        let baseMascotRect = layout.mascotRect
        let mascotRect = asset.renderer == .fallback
            ? baseMascotRect.insetBy(
                dx: -(baseMascotRect.width * (pulse - 1) / 2),
                dy: -(baseMascotRect.height * (pulse - 1) / 2)
            )
            : baseMascotRect

        NSColor.clear.setFill()
        dirtyRect.fill()

        drawFrame(frameStyle, in: bounds)

        if event.type == .attention && asset.renderer == .fallback {
            drawRipple(center: NSPoint(x: mascotRect.midX, y: mascotRect.midY), progress: progress, accent: accent)
        }

        if asset.renderer == .fallback {
            accent.withAlphaComponent(0.96).setFill()
            NSBezierPath(ovalIn: mascotRect).fill()
        }

        if hasBubble {
            drawSpeechBubble(in: bubbleRect, accent: accent, skin: bubbleSkin)
            drawLabel(in: bubbleRect, skin: bubbleSkin, fontSize: layout.labelFontSize)
            drawOKButton(in: layout.okRect, skin: bubbleSkin)
        }

        drawMascot(in: mascotRect, progress: progress, accent: accent)
    }

    /// Draw the frame panel behind the content: a rounded rect filled then stroked, with a soft
    /// shadow when requested. A fully transparent style (e.g. `FrameSkin.none`) draws nothing.
    private func drawFrame(_ style: FrameStyle, in rect: NSRect) {
        guard style.fillColor.a > 0 || (style.strokeColor.a > 0 && style.strokeWidth > 0) else { return }
        let inset = max(style.strokeWidth / 2, 1)
        let panelRect = rect.insetBy(dx: inset + 2, dy: inset + 2)
        let radius = style.cornerRadius * overlayScale
        let path = NSBezierPath(roundedRect: panelRect, xRadius: radius, yRadius: radius)

        NSGraphicsContext.saveGraphicsState()
        if style.hasShadow {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
            shadow.shadowBlurRadius = 12
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.set()
        }
        if style.fillColor.a > 0 {
            nsColor(from: style.fillColor).setFill()
            path.fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        if style.strokeColor.a > 0, style.strokeWidth > 0 {
            nsColor(from: style.strokeColor).setStroke()
            path.lineWidth = style.strokeWidth
            path.stroke()
        }
    }

    private func nsColor(from color: FrameColor) -> NSColor {
        NSColor(
            calibratedRed: CGFloat(color.r),
            green: CGFloat(color.g),
            blue: CGFloat(color.b),
            alpha: CGFloat(color.a)
        )
    }

    private func overlayLayout() -> OverlayLayout {
        let base = OverlayWindow.baseLayout(label: label)
        let scale = overlayScale
        return OverlayLayout(
            mascotRect: base.mascot.scaled(by: scale),
            bubbleRect: base.bubble.scaled(by: scale),
            okRect: base.ok.scaled(by: scale),
            hasBubble: base.hasBubble,
            labelFontSize: base.labelFontSize * scale
        )
    }

    private func drawRipple(center: NSPoint, progress: Double, accent: NSColor) {
        let radius = CGFloat(44 + progress * 56)
        let alpha = CGFloat(1 - progress) * 0.25
        accent.withAlphaComponent(alpha).setStroke()
        let rect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let path = NSBezierPath(ovalIn: rect)
        path.lineWidth = 3
        path.stroke()
    }

    private var backingScale: CGFloat {
        window?.backingScaleFactor ?? 2
    }

    private func drawMascot(in rect: NSRect, progress: Double, accent: NSColor) {
        let animation: ClaudeCodeAnimation?
        switch asset.renderer {
        case .claudePixelRightHandWave:
            animation = .rightHandWave
        case .claudePixelSquintLegWave:
            animation = .squintLegWave
        case .fallback:
            animation = nil
        }
        if let animation {
            ClaudeCrabArt.draw(
                in: rect,
                animation: animation,
                eventType: event.type,
                progress: progress,
                backingScale: backingScale
            )
            return
        }

        let symbol = event.source == .claudeCode ? "C" : "O"
        let status = event.type == .done ? "✓" : "!"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 48, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let symbolText = symbol as NSString
        let symbolSize = symbolText.size(withAttributes: attributes)
        symbolText.draw(
            at: NSPoint(x: rect.midX - symbolSize.width / 2, y: rect.midY - symbolSize.height / 2),
            withAttributes: attributes
        )

        let statusAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .heavy),
            .foregroundColor: accent
        ]
        let yOffset = CGFloat(sin(progress * .pi * 2)) * 4
        (status as NSString).draw(
            at: NSPoint(x: rect.maxX - 10, y: rect.maxY - 22 + yOffset),
            withAttributes: statusAttributes
        )
    }

    /// Draws the (auto-fit) session label. The bubble was already sized to the text in `baseLayout`,
    /// so here we just place it: monospace for Windows XP, inset on the left to clear the pixel tail.
    private func drawLabel(in rect: NSRect, skin: OverlaySkin, fontSize: CGFloat) {
        let display = OverlayWindow.displayLabel(label)
        guard !display.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let text = display as NSString
        let size = max(fontSize, 6)
        let font: NSFont = skin == .windowsXP
            ? .monospacedSystemFont(ofSize: size, weight: .bold)
            : .systemFont(ofSize: size, weight: .bold)

        let leftInset: CGFloat
        let rightInset: CGFloat
        switch skin {
        case .windowsXP:
            // Text sits to the right of the tail; insets mirror the base-layout padding.
            leftInset = OverlayWindow.bubblePadLeft * overlayScale
            rightInset = OverlayWindow.bubblePadRight * overlayScale
        case .classicPixel:
            let symmetric = (OverlayWindow.bubblePadLeft + OverlayWindow.bubblePadRight) / 2 * overlayScale
            leftInset = symmetric
            rightInset = symmetric
        }
        let insetRect = NSRect(
            x: rect.minX + leftInset,
            y: rect.minY,
            width: max(rect.width - leftInset - rightInset, 1),
            height: rect.height
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: labelColor(for: skin),
            .paragraphStyle: paragraph
        ]
        let textSize = text.size(withAttributes: attributes)
        let drawRect = NSRect(
            x: insetRect.minX,
            y: insetRect.midY - textSize.height / 2,
            width: insetRect.width,
            height: textSize.height
        )
        text.draw(in: drawRect, withAttributes: attributes)
    }

    private func labelColor(for skin: OverlaySkin) -> NSColor {
        switch skin {
        case .windowsXP:
            return NSColor(calibratedRed: 0.04, green: 0.12, blue: 0.38, alpha: 1)
        case .classicPixel:
            return NSColor(calibratedWhite: 0.08, alpha: 1)
        }
    }

    private func drawSpeechBubble(in rect: NSRect, accent: NSColor, skin: OverlaySkin) {
        switch skin {
        case .windowsXP:
            drawWindowsXPSpeechBubble(in: rect, accent: accent)
        case .classicPixel:
            drawClassicPixelSpeechBubble(in: rect, accent: accent)
        }
    }

    private func drawWindowsXPSpeechBubble(in rect: NSRect, accent: NSColor) {
        XPBubbleArt.drawSpeechBubble(in: rect, backingScale: backingScale)
    }

    private func drawClassicPixelSpeechBubble(in rect: NSRect, accent: NSColor) {
        let tailWidth: CGFloat = 6
        let tailHeight: CGFloat = 10
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX, y: rect.midY + tailHeight / 2))
        path.line(to: NSPoint(x: rect.minX - tailWidth, y: rect.midY + tailHeight / 2))
        path.line(to: NSPoint(x: rect.minX - tailWidth, y: rect.midY - tailHeight / 2))
        path.line(to: NSPoint(x: rect.minX, y: rect.midY - tailHeight / 2))
        path.close()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.shouldAntialias = false
        NSColor.white.withAlphaComponent(0.97).setFill()
        path.fill()
        accent.setStroke()
        path.lineWidth = 1
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawOKButton(in rect: NSRect, skin: OverlaySkin) {
        switch skin {
        case .windowsXP:
            drawWindowsXPOKButton(in: rect)
        case .classicPixel:
            drawClassicPixelOKButton(in: rect)
        }
    }

    private func drawWindowsXPOKButton(in rect: NSRect) {
        XPBubbleArt.drawButton(in: rect, backingScale: backingScale)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let fontSize = max(min(rect.height * 0.42, 12), 7)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        let text = "OK" as NSString
        let textSize = text.size(withAttributes: attributes)
        let textRect = NSRect(
            x: rect.minX,
            y: rect.midY - textSize.height / 2,
            width: rect.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)
    }

    private func drawClassicPixelOKButton(in rect: NSRect) {
        let fill = NSColor(calibratedRed: 0.18, green: 0.74, blue: 0.32, alpha: 0.98)
        let stroke = NSColor(calibratedRed: 0.04, green: 0.36, blue: 0.12, alpha: 1)
        drawPixelBox(in: rect, fill: fill, stroke: stroke)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 7, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        ("OK" as NSString).draw(in: rect.insetBy(dx: 0, dy: 2), withAttributes: attributes)
    }

    private func drawPixelBox(in rect: NSRect, fill: NSColor, stroke: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.shouldAntialias = false
        fill.setFill()
        rect.fill()
        stroke.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}

private struct OverlayLayout {
    var mascotRect: NSRect
    var bubbleRect: NSRect
    var okRect: NSRect
    var hasBubble: Bool
    var labelFontSize: CGFloat
}

private extension NSSize {
    func scaled(by scale: CGFloat) -> NSSize {
        NSSize(width: width * scale, height: height * scale)
    }
}

private extension NSRect {
    func scaled(by scale: CGFloat) -> NSRect {
        NSRect(
            x: origin.x * scale,
            y: origin.y * scale,
            width: size.width * scale,
            height: size.height * scale
        )
    }
}

