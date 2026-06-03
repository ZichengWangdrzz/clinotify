import AppKit
import CLINotifyShared
import Foundation

// Enforce a single running helper BEFORE the app starts, so a duplicate never shows a menu-bar icon
// or steals the IPC socket from the live instance. The lock is held for the whole process lifetime.
let instanceGuard = SingleInstanceGuard()
guard instanceGuard.acquire() else {
    FileHandle.standardError.write(Data("CLINotify: another helper is already running; exiting.\n".utf8))
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
