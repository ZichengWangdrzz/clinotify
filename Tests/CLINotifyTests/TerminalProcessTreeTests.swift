import XCTest
@testable import CLINotifyShared

final class TerminalProcessTreeTests: XCTestCase {
    /// Build an injectable lookup closure from a synthetic process tree.
    private func lookup(_ tree: [Int32: (ppid: Int32, name: String)]) -> (Int32) -> (ppid: Int32, name: String)? {
        { tree[$0] }
    }

    func testClimbsToOwningTerminalApp() {
        let tree: [Int32: (ppid: Int32, name: String)] = [
            100: (90, "node"), // claude code
            90: (80, "zsh"),
            80: (1, "iTerm2") // terminal app
        ]
        let result = Terminal.windowOwnerPID(forShellPID: 100, lookup: lookup(tree))
        XCTAssertEqual(result?.pid, 80)
        XCTAssertEqual(result?.bundleHint, "com.googlecode.iterm2")
    }

    func testReturnsNilWhenNoTerminalAncestor() {
        let tree: [Int32: (ppid: Int32, name: String)] = [
            300: (1, "launchd-child")
        ]
        XCTAssertNil(Terminal.windowOwnerPID(forShellPID: 300, lookup: lookup(tree)))
    }

    func testReturnsNilWhenLookupFails() {
        XCTAssertNil(Terminal.windowOwnerPID(forShellPID: 999, lookup: { _ in nil }))
    }

    func testDepthCapTerminatesOnCycle() {
        let tree: [Int32: (ppid: Int32, name: String)] = [
            200: (201, "a"),
            201: (200, "b")
        ]
        // No terminal in the cycle; must terminate (not hang) and return nil.
        XCTAssertNil(Terminal.windowOwnerPID(forShellPID: 200, maxDepth: 8, lookup: lookup(tree)))
    }

    func testMatchesTerminalAtRootImmediately() {
        let tree: [Int32: (ppid: Int32, name: String)] = [
            50: (1, "ghostty")
        ]
        let result = Terminal.windowOwnerPID(forShellPID: 50, lookup: lookup(tree))
        XCTAssertEqual(result?.pid, 50)
        XCTAssertEqual(result?.bundleHint, "com.mitchellh.ghostty")
    }
}
