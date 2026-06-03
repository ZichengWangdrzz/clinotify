import AppKit
import CLINotifyShared
import Foundation
import os

/// Owns the on-screen toasts. There is exactly ONE toast per agent session (keyed by
/// `AgentEvent.sessionKey` — the agent session id, never the tty), stacked at a fixed corner of the
/// PRIMARY (menu-bar) display. The toast never targets a terminal window, so it works identically on
/// every local terminal and the old wrong-terminal targeting bug is impossible by construction.
final class OverlayManager {
    private static let logger = Logger(subsystem: "app.clinotify", category: "overlay")

    /// Maximum simultaneously-visible toasts before older ones are coalesced (future: "+N more").
    private static let maxVisible = 5

    /// Live toasts keyed by `sessionKey`. One window per session; a new event for the same session
    /// replaces its window in place rather than stacking a duplicate.
    private var windows: [String: OverlayWindow] = [:]
    /// Display order of `sessionKey`s, newest last; drives the vertical stack index.
    private var order: [String] = []
    /// The screen the stack currently lives on (the primary display), retained for reflow.
    private var screen: NSScreen?
    private var screenObserver: NSObjectProtocol?

    init() {
        // Re-slot the stack onto the (possibly new) primary display when the screen layout changes
        // (display added/removed, resolution change). Runs on the main queue.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenParametersChanged()
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    /// Show (or replace) the toast for `event`'s session.
    func show(
        event: AgentEvent,
        label: String?,
        settings: SettingsStore,
        capabilities: LicenseCapabilities,
        preferences: NotificationPreferences
    ) {
        DispatchQueue.main.async {
            let asset = AnimationAsset.asset(source: event.source, type: event.type, preferences: preferences)
            let bubbleSkin = BubbleSkinCatalog.selectedSkin(for: event.source, preferences: preferences)
            let frameStyle = FrameCatalog.selectedSkin(for: event.source, preferences: preferences).style
            let resolvedLabel = capabilities.sessionBubble ? label : nil
            let targetScreen = settings.targetScreen(capabilities: capabilities)
            self.screen = targetScreen

            let key = event.sessionKey
            // Replace in place: reuse the existing slot so a session's repeated events don't restack.
            let stackIndex = self.order.firstIndex(of: key) ?? self.order.count
            let previous = self.windows[key]

            let window = OverlayWindow(
                event: event,
                label: resolvedLabel,
                screen: targetScreen,
                asset: asset,
                bubbleSkin: bubbleSkin,
                frameStyle: frameStyle,
                overlayScale: preferences.overlayScale,
                stackIndex: stackIndex,
                onClosed: { [weak self] closed in
                    self?.handleClosed(closed)
                }
            )
            if self.windows[key] == nil {
                self.order.append(key)
            }
            self.windows[key] = window
            // Tear down the prior window for this session AFTER reseating the mapping, so its close
            // handler (which matches by identity) is a no-op and never disturbs the replacement.
            previous?.dismiss()

            // Never steal focus from the user's terminal: order front without activating the app.
            window.orderFrontRegardless()

            // Cap the visible stack: evict the OLDEST toast(s) so the column never overflows the
            // screen. (A coalesced "+N more" badge is a future refinement.)
            self.enforceVisibleCap()
        }
    }

    /// Slide the oldest toasts out until at most `maxVisible` remain. The newest (just-shown) toast is
    /// at the end of `order`, so eviction always targets the front.
    private func enforceVisibleCap() {
        while order.count > Self.maxVisible, let oldest = order.first {
            windows[oldest]?.dismiss()
        }
    }

    /// Dismiss the toast bound to a raw agent session id (the un-namespaced `session_id` / thread-id),
    /// regardless of source. Used by the Claude Code UserPromptSubmit / SessionEnd hooks.
    func dismiss(sessionID: String) {
        DispatchQueue.main.async {
            let keys = self.order.filter { Self.identity(ofKey: $0) == sessionID }
            for key in keys { self.windows[key]?.dismiss() }
        }
    }

    /// Remove a closed toast and slide the remaining ones up to close the gap.
    private func handleClosed(_ closed: OverlayWindow) {
        guard let key = windows.first(where: { $0.value === closed })?.key else { return }
        windows[key] = nil
        order.removeAll { $0 == key }
        reflow()
    }

    private func reflow() {
        let onScreen = screen ?? .primaryDisplay
        // Animated: the toasts below the removed one slide UP to close the gap.
        for (index, key) in order.enumerated() {
            windows[key]?.move(toStackIndex: index, on: onScreen, animated: true)
        }
    }

    /// Re-slot the whole stack onto the current primary display (instant) after a screen-layout change.
    private func handleScreenParametersChanged() {
        let onScreen = NSScreen.primaryDisplay
        screen = onScreen
        for (index, key) in order.enumerated() {
            windows[key]?.move(toStackIndex: index, on: onScreen, animated: false)
        }
    }

    /// The raw agent session id encoded in a `sessionKey` ("<source>:<id>").
    private static func identity(ofKey key: String) -> String {
        let parts = key.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        return parts.count == 2 ? String(parts[1]) : key
    }
}
