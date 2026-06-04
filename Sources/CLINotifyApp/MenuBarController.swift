import AppKit
import CLINotifyShared
import Foundation

final class MenuBarController: NSObject {
    private let settings: SettingsStore
    private let registry: SessionRegistry
    private let eventRouter: EventRouter
    private let licenseController: LicenseController
    private let installer = Installer()
    private var settingsWindowController: SettingsWindowController?
    private var statusItem: NSStatusItem?

    init(settings: SettingsStore, registry: SessionRegistry, eventRouter: EventRouter, licenseController: LicenseController) {
        self.settings = settings
        self.registry = registry
        self.eventRouter = eventRouter
        self.licenseController = licenseController
    }

    func install(startupError: Error? = nil) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Mark the dev channel's icon so it's distinguishable from a production install running beside it.
        item.button?.title = AppChannel.current == .dev ? "CLI·dev" : "CLI"
        item.button?.toolTip = AppChannel.current.displayName
        statusItem = item

        let menu = NSMenu()
        if let startupError {
            let errorItem = NSMenuItem(title: "Startup error: \(startupError.localizedDescription)", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
            menu.addItem(.separator())
        }
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",", target: self))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Test Claude Done", action: #selector(testClaudeDone), keyEquivalent: "", target: self))
        menu.addItem(NSMenuItem(title: "Test Codex Attention", action: #selector(testCodexAttention), keyEquivalent: "", target: self))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Install Hooks", action: #selector(installHooks), keyEquivalent: "", target: self))
        menu.addItem(NSMenuItem(title: "Uninstall Hooks", action: #selector(uninstallHooks), keyEquivalent: "", target: self))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q", target: self))
        item.menu = menu
    }

    @objc private func openSettings() {
        let controller = settingsWindowController ?? SettingsWindowController(
            settings: settings,
            registry: registry,
            licenseController: licenseController
        )
        settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func testClaudeDone() {
        let event = AgentEvent(
            source: .claudeCode,
            type: .done,
            tty: Terminal.currentTTY(),
            cwd: FileManager.default.currentDirectoryPath,
            session: "manual-test",
            title: "Action needed"
        )
        eventRouter.route(event, bypassRegistry: true)
    }

    @objc private func testCodexAttention() {
        let event = AgentEvent(
            source: .codex,
            type: .attention,
            tty: Terminal.currentTTY(),
            cwd: FileManager.default.currentDirectoryPath,
            session: "manual-test",
            title: "Action needed"
        )
        eventRouter.route(event, bypassRegistry: true)
    }

    @objc private func installHooks() {
        do {
            try installer.install()
            // A Finder-launched app gets a minimal PATH that can't see the user's shell, so we can't tell
            // whether ~/.local/bin is actually on their PATH — give an informational note rather than a
            // (always-firing) warning, so the `clinotify` CLI isn't a mysterious "command not found".
            let cli = AppChannel.current.cliName
            let bin = PathEnvironment.binDirectory().path
            showAlert(message: "Hooks installed.\n\nThe \(cli) command is at \(bin)/\(cli). If `\(cli)` isn't found in your terminal, add \(bin) to your PATH.")
        } catch {
            showAlert(message: "Install failed: \(error.localizedDescription)")
        }
    }

    @objc private func uninstallHooks() {
        // Disable autostart first so launchd KeepAlive can't relaunch the daemon after removal — the
        // same teardown the CLI runs. Harmless no-op when autostart was never enabled.
        LaunchAgentControl.disable(for: AppChannel.current)
        do {
            try installer.uninstall()
            showAlert(message: "Hooks removed.")
        } catch {
            showAlert(message: "Uninstall failed: \(error.localizedDescription)")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "CLINotify"
        alert.informativeText = message
        alert.runModal()
    }
}

private extension NSMenuItem {
    convenience init(title: String, action: Selector?, keyEquivalent: String, target: AnyObject) {
        self.init(title: title, action: action, keyEquivalent: keyEquivalent)
        self.target = target
    }
}
