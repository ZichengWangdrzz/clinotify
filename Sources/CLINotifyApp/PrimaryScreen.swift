import AppKit

extension NSScreen {
    /// The PRIMARY (menu-bar) display — the screen whose frame origin is (0, 0) in the global
    /// coordinate space. This is deliberately NOT `NSScreen.main`, which is the screen that currently
    /// holds keyboard focus and therefore moves as the user switches windows. Toasts must always land
    /// on the menu-bar display regardless of where focus is.
    static var primaryDisplay: NSScreen {
        screens.first { $0.frame.origin == .zero } ?? main ?? screens[0]
    }
}
