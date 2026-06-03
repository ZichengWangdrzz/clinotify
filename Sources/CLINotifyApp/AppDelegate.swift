import AppKit
import CLINotifyShared
import Darwin
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let registry = SessionRegistry()
    private let overrideStore = SessionOverrideStore()
    private let licenseController = LicenseController()
    private let soundManager = SoundManager()
    private let overlayManager = OverlayManager()
    private lazy var eventRouter = EventRouter(
        settings: settings,
        registry: registry,
        overrideStore: overrideStore,
        licenseController: licenseController,
        soundManager: soundManager,
        overlayManager: overlayManager
    )
    private lazy var ipcServer = IPCServer(
        registry: registry,
        overrideStore: overrideStore,
        eventRouter: eventRouter
    )
    private lazy var menuBarController = MenuBarController(
        settings: settings,
        registry: registry,
        eventRouter: eventRouter,
        licenseController: licenseController
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGPIPE, SIG_IGN)
        do {
            try ApplicationPaths.ensureApplicationSupportDirectory()
            try ipcServer.start()
            menuBarController.install()
        } catch {
            menuBarController.install(startupError: error)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ipcServer.stop()
    }
}
