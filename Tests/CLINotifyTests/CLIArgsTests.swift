import Foundation
import XCTest
@testable import CLINotifyShared

/// The redesigned CLI exposes top-level skin/sound/frame/animation verbs and a simple `test`
/// verb. The arg-shaping logic lives in CLIArgs (pure, in the shared lib) so it is testable
/// without driving the executable's @main. These tests pin that logic.
final class CLIArgsTests: XCTestCase {
    // MARK: - withDefaultAgent

    func testWithDefaultAgentPrependsClaudeCodeWhenAgentOmitted() {
        // `clinotify bubble windows-xp` -> handler sees ["claude-code", "windows-xp"]
        XCTAssertEqual(CLIArgs.withDefaultAgent(["windows-xp"]), ["claude-code", "windows-xp"])
        // `clinotify bubble` (list) -> ["claude-code"]
        XCTAssertEqual(CLIArgs.withDefaultAgent([]), ["claude-code"])
        // value-with-flags is preserved after the injected agent
        XCTAssertEqual(
            CLIArgs.withDefaultAgent(["glass", "--tty", "/dev/ttys003"]),
            ["claude-code", "glass", "--tty", "/dev/ttys003"]
        )
    }

    func testWithDefaultAgentPassesThroughExplicitAgent() {
        // Legacy / explicit form must not get a second agent injected.
        XCTAssertEqual(CLIArgs.withDefaultAgent(["claude-code", "windows-xp"]), ["claude-code", "windows-xp"])
        XCTAssertEqual(CLIArgs.withDefaultAgent(["codex"]), ["codex"])
    }

    // MARK: - parseTestArgs

    func testParseTestDefaults() {
        let inv = CLIArgs.parseTestArgs([])
        XCTAssertEqual(inv.type, .done)
        XCTAssertEqual(inv.label, "Action needed")
        // session defaults to the label so distinct labels stack and a repeat replaces in place.
        XCTAssertEqual(inv.session, "Action needed")
    }

    func testParseTestPositionalType() {
        XCTAssertEqual(CLIArgs.parseTestArgs(["attention"]).type, .attention)
        XCTAssertEqual(CLIArgs.parseTestArgs(["done"]).type, .done)
        // Unknown positional falls back to done rather than erroring.
        XCTAssertEqual(CLIArgs.parseTestArgs(["bogus"]).type, .done)
    }

    func testParseTestFlags() {
        let inv = CLIArgs.parseTestArgs(["done", "--label", "Build backend"])
        XCTAssertEqual(inv.type, .done)
        XCTAssertEqual(inv.label, "Build backend")
        XCTAssertEqual(inv.session, "Build backend")
        // --type flag wins, --session overrides the label-derived default.
        let inv2 = CLIArgs.parseTestArgs(["--type", "attention", "--label", "X", "--session", "sess-1"])
        XCTAssertEqual(inv2.type, .attention)
        XCTAssertEqual(inv2.session, "sess-1")
    }

    func testParseTestToleratesLegacyClaudeCodePositional() {
        // Old docs/muscle memory: `clinotify test claude-code --type attention`
        let inv = CLIArgs.parseTestArgs(["claude-code", "--type", "attention", "--label", "Need input"])
        XCTAssertEqual(inv.type, .attention)
        XCTAssertEqual(inv.label, "Need input")
    }

    // MARK: - Edge cases (regression guards from the verification review)

    func testTrailingValuelessFlagIsDroppedNotDoubleConsumed() {
        // A trailing `--flag` with no value must not corrupt positional parsing.
        XCTAssertEqual(CLIArgs.positionalValues(["a", "--label"]), ["a"])
        XCTAssertEqual(CLIArgs.positionalValues(["--label"]), [])
        XCTAssertEqual(CLIArgs.positionalValues(["done", "--label"]), ["done"])
        // ...and a trailing flag still leaves the positional type intact in parseTestArgs.
        XCTAssertEqual(CLIArgs.parseTestArgs(["attention", "--label"]).type, .attention)
    }

    func testTypeFlagBeatsPositionalType() {
        // Documented precedence: an explicit --type flag wins over a positional type token.
        XCTAssertEqual(CLIArgs.parseTestArgs(["attention", "--type", "done"]).type, .done)
    }

    // MARK: - background on|off|toggle  (the friendly name for the frame axis)

    func testBackgroundTargetMapping() {
        // on => the visible panel/card, off => no frame.
        XCTAssertEqual(CLIArgs.backgroundTarget("on", current: .none), .panel)
        XCTAssertEqual(CLIArgs.backgroundTarget("off", current: .panel), FrameSkin.none)
        // toggle flips whatever is current.
        XCTAssertEqual(CLIArgs.backgroundTarget("toggle", current: .panel), FrameSkin.none)
        XCTAssertEqual(CLIArgs.backgroundTarget("toggle", current: .none), .panel)
        // unknown action => nil (caller prints usage).
        XCTAssertNil(CLIArgs.backgroundTarget("bogus", current: .panel))
    }

    // MARK: - eventTitle  (don't let Claude's verbose status message override the toast label)

    func testEventTitleDropsClaudeStatusMessage() {
        // Claude Code's Notification hook passes a changing status `message`. We intentionally do
        // NOT surface it: the toast's presence already means "needs you", so the label must stay a
        // stable identifier. With no explicit title, eventTitle returns nil and displayLabel then
        // falls back to the project (cwd basename), never to "Claude is waiting for your input".
        XCTAssertNil(CLIArgs.eventTitle(source: .claudeCode, title: nil, message: "Claude is waiting for your input"))
        XCTAssertNil(CLIArgs.eventTitle(source: .claudeCode, title: "", message: "Claude needs your permission to use Bash"))
    }

    func testEventTitleKeepsExplicitClaudeTitle() {
        // An explicit title (e.g. a `--label`) is a deliberate label, not the noisy status — keep it.
        XCTAssertEqual(CLIArgs.eventTitle(source: .claudeCode, title: "Build backend", message: "Claude is waiting"), "Build backend")
    }

    func testEventTitleKeepsCodexMessage() {
        // Codex's message is its actual content (the summary of what it did), so it stays the label.
        XCTAssertEqual(CLIArgs.eventTitle(source: .codex, title: nil, message: "Refactored auth module"), "Refactored auth module")
        XCTAssertEqual(CLIArgs.eventTitle(source: .codex, title: "Explicit", message: "msg"), "Explicit")
        XCTAssertNil(CLIArgs.eventTitle(source: .codex, title: nil, message: nil))
    }

    // MARK: - isIdleNudge  (drop Claude Code's idle_prompt so a dismissed toast doesn't re-spawn)

    func testIsIdleNudgeOnlyForClaudeIdlePrompt() {
        // The "you've been idle" nag re-fires while the user is away and would re-create a toast they
        // already dismissed — drop it.
        XCTAssertTrue(CLIArgs.isIdleNudge(source: .claudeCode, notificationType: "idle_prompt"))
        // Genuine "needs you" notifications must pass through.
        XCTAssertFalse(CLIArgs.isIdleNudge(source: .claudeCode, notificationType: "permission_prompt"))
        XCTAssertFalse(CLIArgs.isIdleNudge(source: .claudeCode, notificationType: "elicitation_dialog"))
        // Absent notification_type (Stop/done, or older Claude Code) -> never suppressed (safe default).
        XCTAssertFalse(CLIArgs.isIdleNudge(source: .claudeCode, notificationType: nil))
        XCTAssertFalse(CLIArgs.isIdleNudge(source: .claudeCode, notificationType: ""))
        // Codex has no idle_prompt concept; never suppress it on this basis.
        XCTAssertFalse(CLIArgs.isIdleNudge(source: .codex, notificationType: "idle_prompt"))
    }
}
