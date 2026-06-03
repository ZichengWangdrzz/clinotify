import Foundation

public enum EventSource: String, Codable, CaseIterable, Sendable {
    case claudeCode = "claude_code"
    case codex
}

public enum EventType: String, Codable, CaseIterable, Sendable {
    case done
    case attention
}

public struct AgentEvent: Codable, Equatable, Sendable {
    public var source: EventSource
    public var type: EventType
    public var tty: String?
    public var cwd: String?
    public var session: String?
    public var title: String?
    /// PID of the CLI process that emitted the event (the shell-side hook), if known.
    public var senderPID: Int32?
    /// Parent PID of the emitting CLI process, used to climb toward the owning terminal app.
    public var senderPPID: Int32?

    public init(
        source: EventSource,
        type: EventType,
        tty: String?,
        cwd: String?,
        session: String?,
        title: String?,
        senderPID: Int32? = nil,
        senderPPID: Int32? = nil
    ) {
        self.source = source
        self.type = type
        self.tty = tty
        self.cwd = cwd
        self.session = session
        self.title = title
        self.senderPID = senderPID
        self.senderPPID = senderPPID
    }

    /// Stable identity of the on-screen toast this event belongs to. Keyed by the AGENT-provided
    /// session id (Claude Code `session_id`, Codex thread-id) — NOT the tty, which gets reused across
    /// sessions and would bleed one session's state into another. Namespaced by source so a Claude and
    /// a Codex session can never collide. Falls back to the tty, then a constant, only if no id exists.
    public var sessionKey: String {
        let identity = session.flatMap { $0.isEmpty ? nil : $0 }
            ?? tty.flatMap { $0.isEmpty ? nil : $0 }
            ?? "unknown"
        return "\(source.rawValue):\(identity)"
    }

    /// The human-facing label for the toast bubble / fallback notification: an explicit title wins
    /// (e.g. `--label`, or a session name), then the working-directory basename (the project the user
    /// recognizes), then the agent name.
    public var displayLabel: String {
        if let title, !title.isEmpty { return title }
        if let cwd, !cwd.isEmpty {
            let base = (cwd as NSString).lastPathComponent
            if !base.isEmpty, base != "/" { return base }
        }
        return source == .codex ? "Codex" : "Claude Code"
    }
}

public struct SessionRegistration: Codable, Equatable, Identifiable, Sendable {
    public var id: String { tty }
    public var tty: String
    public var name: String
    public var cwd: String?
    public var source: EventSource?
    public var updatedAt: Date
    /// PID of the CLI process that registered the session.
    public var pid: Int32?
    /// Parent PID of the registering process.
    public var ppid: Int32?
    /// Bundle identifier hint for the owning terminal app, when resolvable at registration time.
    public var terminalBundleID: String?

    public init(
        tty: String,
        name: String,
        cwd: String?,
        source: EventSource? = nil,
        updatedAt: Date = Date(),
        pid: Int32? = nil,
        ppid: Int32? = nil,
        terminalBundleID: String? = nil
    ) {
        self.tty = tty
        self.name = name
        self.cwd = cwd
        self.source = source
        self.updatedAt = updatedAt
        self.pid = pid
        self.ppid = ppid
        self.terminalBundleID = terminalBundleID
    }
}

public enum IPCCommand: String, Codable, Sendable {
    case event
    case dismiss
    case register
    case unregister
    case list
    case setOverride
    case getOverride
}

public struct IPCEnvelope: Codable, Sendable {
    public var command: IPCCommand
    public var event: AgentEvent?
    public var registration: SessionRegistration?
    public var tty: String?
    /// Agent session id for `.dismiss` (the `session_id` / thread-id, NOT namespaced) — dismisses the
    /// toast bound to that session regardless of which source/tty it came from.
    public var session: String?
    public var bypassRegistry: Bool
    /// Per-terminal override payload for `.setOverride` (merged over any existing override).
    public var override: SessionPreferenceOverride?

    public init(
        command: IPCCommand,
        event: AgentEvent? = nil,
        registration: SessionRegistration? = nil,
        tty: String? = nil,
        session: String? = nil,
        bypassRegistry: Bool = false,
        override: SessionPreferenceOverride? = nil
    ) {
        self.command = command
        self.event = event
        self.registration = registration
        self.tty = tty
        self.session = session
        self.bypassRegistry = bypassRegistry
        self.override = override
    }
}

public struct IPCResponse: Codable, Sendable {
    public var ok: Bool
    public var message: String?
    public var sessions: [SessionRegistration]?
    /// Resolved per-terminal override returned for `.getOverride`.
    public var override: SessionPreferenceOverride?

    public init(
        ok: Bool,
        message: String? = nil,
        sessions: [SessionRegistration]? = nil,
        override: SessionPreferenceOverride? = nil
    ) {
        self.ok = ok
        self.message = message
        self.sessions = sessions
        self.override = override
    }
}
