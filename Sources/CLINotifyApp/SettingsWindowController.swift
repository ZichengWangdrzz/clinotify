import AppKit
import CLINotifyShared
import SwiftUI

final class SettingsWindowController: NSWindowController {
    init(settings: SettingsStore, registry: SessionRegistry, licenseController: LicenseController) {
        let view = SettingsView(settings: settings, registry: registry, licenseController: licenseController)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "CLINotify Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 560, height: 520))
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        nil
    }
}
