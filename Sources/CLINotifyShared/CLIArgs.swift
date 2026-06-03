import Foundation

/// Pure argument-shaping for the `clinotify` CLI's redesigned top-level surface.
///
/// The CLI exposes ergonomic top-level verbs (`clinotify bubble <id>`, `clinotify test`, ...)
/// that delegate to the existing per-agent handlers. Keeping the shaping logic here — in the
/// shared library, free of side effects — lets it be unit-tested without driving the
/// executable's `@main` entry point.
public enum CLIArgs {
    /// Agents that own per-agent skins. Claude Code is the only one with skins today; Codex is
    /// listed so an explicit `codex` positional is treated as an agent, not a skin id.
    public static let knownAgents: Set<String> = ["claude-code", "codex"]

    /// Top-level skin verbs (`clinotify bubble windows-xp`) default the agent to `claude-code`,
    /// so users don't have to type the redundant positional. If the caller already named a known
    /// agent (legacy `clinotify settings skin claude-code ...` muscle memory, or `codex`), the
    /// args pass through unchanged.
    public static func withDefaultAgent(_ args: [String], default defaultAgent: String = "claude-code") -> [String] {
        if let first = args.first, knownAgents.contains(first) {
            return args
        }
        return [defaultAgent] + args
    }

    /// The resolved shape of a `clinotify test [...]` invocation.
    public struct TestInvocation: Equatable, Sendable {
        public let type: EventType
        public let label: String
        public let session: String

        public init(type: EventType, label: String, session: String) {
            self.type = type
            self.label = label
            self.session = session
        }
    }

    /// Parse `test [done|attention] [--type X] [--label Y] [--session Z]`.
    ///
    /// Tolerates a leading legacy `claude-code` positional. Defaults: `type=done`,
    /// `label="Manual Test"`, and `session=label` (so two different labels stack as two toasts
    /// while repeating a label replaces in place — see ADR-0002). An unknown type string falls
    /// back to `.done` rather than failing.
    public static func parseTestArgs(_ args: [String]) -> TestInvocation {
        var rest = args
        if rest.first == "claude-code" {
            rest = Array(rest.dropFirst())
        }
        let flags = flagDictionary(rest)
        let positional = positionalValues(rest)
        let typeString = flags["type"] ?? positional.first ?? EventType.done.rawValue
        let type = EventType(rawValue: typeString) ?? .done
        let label = flags["label"] ?? "Action needed"
        let session = flags["session"] ?? label
        return TestInvocation(type: type, label: label, session: session)
    }

    /// Map the `background <on|off|toggle>` verb to a `FrameSkin`. The frame axis has only two
    /// values, so it reads better as an on/off switch: `on` = the visible panel/card behind the
    /// toast, `off` = no frame (mascot + bubble float). `toggle` flips the current value. Returns
    /// `nil` for an unrecognized action so the caller can print usage.
    public static func backgroundTarget(_ action: String, current: FrameSkin) -> FrameSkin? {
        // Qualify FrameSkin.none explicitly: the return type is FrameSkin?, so a bare `.none`
        // would resolve to Optional.none (nil) instead of the FrameSkin case.
        switch action {
        case "on": return FrameSkin.panel
        case "off": return FrameSkin.none
        case "toggle": return current == .panel ? FrameSkin.none : FrameSkin.panel
        default: return nil
        }
    }

    /// The toast label for an incoming hook event.
    ///
    /// Claude Code's `Notification` hook passes a verbose, *changing* status `message`
    /// ("Claude is waiting for your input", "Claude needs your permission to use Bash"). We
    /// intentionally do NOT surface it: once a toast is on screen the user already knows the agent
    /// needs them, so a status string that mutates in place is just noise. For Claude Code we drop
    /// the message and let the label fall back to a stable identifier (the project / cwd basename via
    /// `AgentEvent.displayLabel`). An *explicit* title (e.g. a `--label`) is a deliberate label, not
    /// the noisy status, so it is always kept. Codex keeps its message — for Codex the message IS the
    /// content (the summary of what it did), not a transient status.
    public static func eventTitle(source: EventSource, title: String?, message: String?) -> String? {
        let title = title.flatMap { $0.isEmpty ? nil : $0 }
        switch source {
        case .claudeCode:
            return title // ignore `message`: the toast's presence is the signal, the label is identity.
        case .codex:
            return title ?? message.flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    /// Whether an incoming hook event is Claude Code's `idle_prompt` "nudge" — the notification it
    /// fires after the prompt has sat idle (the user stepped away). It can re-fire while idle, so it
    /// would re-spawn a toast the user already dismissed. We drop it; the genuine "needs you" signals
    /// are `permission_prompt` (Notification), AskUserQuestion/ExitPlanMode (PreToolUse), and `done`
    /// (Stop), none of which carry `notification_type == "idle_prompt"`. Codex has no such concept.
    public static func isIdleNudge(source: EventSource, notificationType: String?) -> Bool {
        source == .claudeCode && notificationType == "idle_prompt"
    }

    /// Collect `--key value` pairs into a dictionary (keys without the leading `--`).
    public static func flagDictionary(_ args: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var index = 0
        while index < args.count {
            let key = args[index]
            guard key.hasPrefix("--"), index + 1 < args.count else {
                index += 1
                continue
            }
            result[String(key.dropFirst(2))] = args[index + 1]
            index += 2
        }
        return result
    }

    /// The non-flag positional arguments, skipping `--key value` pairs.
    public static func positionalValues(_ args: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg.hasPrefix("--") {
                // Skip the flag and its value — but only advance past a value if one exists, so a
                // trailing valueless flag (e.g. `["--label"]`) is dropped, not double-consumed.
                index += (index + 1 < args.count) ? 2 : 1
                continue
            }
            result.append(arg)
            index += 1
        }
        return result
    }
}
