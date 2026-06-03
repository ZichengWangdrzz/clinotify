import CLINotifyShared
import Foundation
import os

final class EventRouter {
    private static let logger = Logger(subsystem: "app.clinotify", category: "event-router")

    private let settings: SettingsStore
    private let registry: SessionRegistry
    private let overrideStore: SessionOverrideStore
    private let licenseController: LicenseController
    private let soundManager: SoundManager
    private let overlayManager: OverlayManager
    private let systemNotificationManager: SystemNotificationManager

    init(
        settings: SettingsStore,
        registry: SessionRegistry,
        overrideStore: SessionOverrideStore,
        licenseController: LicenseController,
        soundManager: SoundManager,
        overlayManager: OverlayManager,
        systemNotificationManager: SystemNotificationManager
    ) {
        self.settings = settings
        self.registry = registry
        self.overrideStore = overrideStore
        self.licenseController = licenseController
        self.soundManager = soundManager
        self.overlayManager = overlayManager
        self.systemNotificationManager = systemNotificationManager
    }

    func route(_ event: AgentEvent, bypassRegistry: Bool = false) {
        let globalPreferences = settings.notificationPreferences()
        guard globalPreferences.globalEnabled else {
            Self.logger.debug("Event dropped: notifications globally disabled.")
            return
        }

        // SET-ONCE / auto-identify: the toast is keyed by the agent session id, so we never need a
        // prior `register` call and must NOT drop events for "unregistered" sessions (the old bug).
        // We still upsert a registration (keyed by tty) so `clinotify list` can show the session.
        let label = event.displayLabel
        if !bypassRegistry, let tty = event.tty, !tty.isEmpty {
            let registration = SessionRegistration(
                tty: tty,
                name: label,
                cwd: event.cwd,
                source: event.source,
                pid: event.senderPID,
                ppid: event.senderPPID
            )
            try? registry.register(registration)
        }

        let capabilities = licenseController.refreshFromDisk()

        // Merge any per-terminal override (keyed by tty) over the global preferences.
        let override = event.tty.flatMap { overrideStore.override(for: $0) } ?? SessionPreferenceOverride()
        let preferences = override.resolved(global: globalPreferences)

        if preferences.soundEnabled {
            soundManager.play(
                for: event,
                settings: settings,
                capabilities: capabilities,
                preferences: preferences
            )
        }
        if preferences.animationEnabled && capabilities.mascotAnimation {
            overlayManager.show(
                event: event,
                label: label,
                settings: settings,
                capabilities: capabilities,
                preferences: preferences
            )
        } else {
            systemNotificationManager.deliver(
                event: event,
                label: capabilities.sessionBubble ? label : nil
            )
        }
    }

    /// Dismiss the toast bound to a raw agent session id (Claude Code UserPromptSubmit / SessionEnd).
    func dismiss(sessionID: String) {
        overlayManager.dismiss(sessionID: sessionID)
    }
}
