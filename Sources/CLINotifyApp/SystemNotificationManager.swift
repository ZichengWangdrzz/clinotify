import AppKit
import CLINotifyObjCSupport
import CLINotifyShared
import Foundation
import os
import UserNotifications

final class SystemNotificationManager {
    private static let logger = Logger(subsystem: "app.clinotify", category: "notifications")
    private var requestedAuthorization = false
    private var notificationsAvailable = true

    func deliver(event: AgentEvent, label: String?) {
        guard requestAuthorizationIfNeeded() else { return }
        let content = UNMutableNotificationContent()
        content.title = event.type == .done ? "Task complete" : "Needs attention"
        content.body = [sourceName(event.source), label, event.title]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
        content.sound = nil
        let request = UNNotificationRequest(
            identifier: "clinotify-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        // UNUserNotificationCenter aborts (uncatchable NSException) on unsigned/improperly-bundled
        // processes; wrap so the daemon degrades gracefully instead of crashing.
        let delivered = CLINotifyRunCatching {
            UNUserNotificationCenter.current().add(request)
        }
        if !delivered {
            notificationsAvailable = false
            Self.logger.notice("System notifications unavailable (UNUserNotificationCenter); event skipped.")
        }
    }

    private func sourceName(_ source: EventSource) -> String {
        switch source {
        case .claudeCode:
            return "Claude Code"
        case .codex:
            return "Codex"
        }
    }

    /// Returns whether the notification center is usable. Probes once and caches the result.
    ///
    /// `UNUserNotificationCenter.current()` asserts `bundleProxyForCurrentProcess is nil` and aborts
    /// when the process has no registered app bundle (e.g. the loose debug executable, which has no
    /// `Info.plist` and therefore no bundle identifier). The exception is thrown inside a
    /// `dispatch_once` block, where libdispatch terminates rather than letting it unwind — so it
    /// cannot be caught and MUST be avoided up front. A real `.app` bundle has a bundle identifier
    /// and is safe. `CLINotifyRunCatching` stays as defense-in-depth for the `add(_:)` path.
    private func requestAuthorizationIfNeeded() -> Bool {
        guard !requestedAuthorization else { return notificationsAvailable }
        requestedAuthorization = true
        guard Bundle.main.bundleIdentifier != nil else {
            notificationsAvailable = false
            Self.logger.notice("No app bundle identifier; system notifications disabled (run the CLINotify.app bundle).")
            return false
        }
        let ok = CLINotifyRunCatching {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        }
        notificationsAvailable = ok
        if !ok {
            Self.logger.notice("UNUserNotificationCenter unavailable for this bundle; system notifications disabled.")
        }
        return ok
    }
}
