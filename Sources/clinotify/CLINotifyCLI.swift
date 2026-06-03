import CLINotifyShared
import Darwin
import Foundation

@main
struct CLINotifyCLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            printUsage()
            return
        }

        switch command {
        case "name":
            handleName(Array(args.dropFirst()))
        case "stop":
            handleClear()
        case "list":
            handleList()
        case "status":
            handleStatus()
        case "launch":
            handleLaunch()
        case "autostart":
            handleAutostart(Array(args.dropFirst()))
        case "license":
            handleLicense(Array(args.dropFirst()))
        case "settings":
            handleSettings(Array(args.dropFirst()))
        case "test":
            handleTest(Array(args.dropFirst()))
        case "event":
            handleEvent(Array(args.dropFirst()))
        case "codex-event":
            handleCodexEvent(Array(args.dropFirst()))
        case "dismiss":
            handleDismiss(Array(args.dropFirst()))
        case "install":
            handleInstall()
        case "uninstall":
            handleUninstall(Array(args.dropFirst()))

        // Top-level skin verbs (ADR: the user-facing surface). Each delegates to the per-agent
        // settings handler with `claude-code` defaulted in, so `clinotify bubble windows-xp`
        // works without the redundant agent positional. No arg => list options.
        case "animation":
            handleAnimationSettings(CLIArgs.withDefaultAgent(Array(args.dropFirst())), store: NotificationPreferencesStore())
        case "bubble", "skin":
            handleSkinSettings(CLIArgs.withDefaultAgent(Array(args.dropFirst())), store: NotificationPreferencesStore())
        case "background":
            handleBackground(Array(args.dropFirst()))
        case "frame": // hidden alias of `background`, parallels `settings frame claude-code <id>`
            handleFrameSettings(CLIArgs.withDefaultAgent(Array(args.dropFirst())), store: NotificationPreferencesStore())
        case "sound":
            handleSoundSettings(CLIArgs.withDefaultAgent(Array(args.dropFirst())), store: NotificationPreferencesStore())
        case "mute":
            handleMuteSetting(Array(args.dropFirst()))
        case "scale":
            handleScaleSetting(Array(args.dropFirst()), store: NotificationPreferencesStore())
        case "alerts":
            handleAlerts(Array(args.dropFirst()))

        case "help", "-h", "--help":
            let rest = Array(args.dropFirst())
            printUsage(advanced: rest.contains("--all") || rest.contains("all") || rest.contains("advanced"))

        default:
            printUsage()
        }
    }

    /// Master on/off for all toasts. `clinotify alerts` prints the current state; `clinotify
    /// alerts on|off` sets it.
    private static func handleAlerts(_ args: [String]) {
        let store = NotificationPreferencesStore()
        guard let value = args.first else {
            print("alerts: \(store.load().globalEnabled ? "on" : "off")")
            return
        }
        handleBooleanSetting(["alerts", value], store: store)
    }

    /// The friendly name for the frame axis: `background on` shows the panel/card behind the toast,
    /// `background off` removes it (mascot + bubble float). `clinotify background` prints the state.
    private static func handleBackground(_ args: [String]) {
        let store = NotificationPreferencesStore()
        guard let action = positionalArgs(args).first else {
            print("background: \(store.load().claudeCodeFrameSkin == .panel ? "on" : "off")")
            return
        }
        guard let target = CLIArgs.backgroundTarget(action, current: store.load().claudeCodeFrameSkin) else {
            printError("Usage: clinotify background [on|off|toggle]")
            return
        }
        guard let updated = try? store.update({ _ = $0.selectClaudeCodeFrameSkin(target) }) else { return }
        print("background: \(updated.claudeCodeFrameSkin == .panel ? "on" : "off")")
    }

    /// Install the hooks + CLI symlink for THIS binary's channel (production via `clinotify`, dev via
    /// `clinotify-dev`). The symlink points at the actually-running binary so it works for any build.
    private static func handleInstall() {
        let selfURL = URL(fileURLWithPath: runningExecutablePath()).resolvingSymlinksInPath()
        do {
            try Installer(cliURLProvider: { selfURL }).install()
            print("Installed CLINotify (\(AppChannel.current.rawValue)): \(AppChannel.current.cliName) CLI + Claude/Codex hooks.")
        } catch {
            printError("Install failed: \(error.localizedDescription)")
        }
    }

    /// Full teardown for this binary's channel. Order matters: disable the autostart LaunchAgent FIRST
    /// (else launchd KeepAlive would relaunch the daemon we are removing), then strip hooks + CLI
    /// symlink, then clean up leftover state. `--purge` also deletes the channel's Application Support
    /// directory (preferences/license/registry); without it those are kept so a reinstall restores the
    /// user's settings, and only the transient socket/lock are swept.
    private static func handleUninstall(_ args: [String] = []) {
        let purge = args.contains("--purge")
        let channel = AppChannel.current
        let selfURL = URL(fileURLWithPath: runningExecutablePath()).resolvingSymlinksInPath()

        // 1. Tear down autostart so a deleted daemon can never be resurrected by launchd KeepAlive.
        //    Harmless no-op if autostart was never enabled.
        LaunchAgentControl.disable(for: channel)

        // 2. Remove hooks + CLI symlink + Codex notify (+ orphaned *.clinotify.bak backups).
        do {
            try Installer(cliURLProvider: { selfURL }).uninstall()
        } catch {
            printError("Uninstall failed: \(error.localizedDescription)")
            return
        }

        // 3. Clean leftover state. The daemon unlinks its socket on normal start/stop, so a lingering
        //    socket/lock only survives an ungraceful kill — best-effort remove them either way.
        let fileManager = FileManager.default
        if purge {
            try? fileManager.removeItem(at: ApplicationPaths.applicationSupportDirectory)
        } else {
            try? fileManager.removeItem(atPath: ApplicationPaths.socketPath)
            try? fileManager.removeItem(atPath: ApplicationPaths.lockPath)
        }

        let stateNote = purge
            ? " state directory purged"
            : " (settings/license kept — use `\(channel.cliName) uninstall --purge` to remove them)"
        print("Uninstalled CLINotify (\(channel.rawValue)): hooks + CLI symlink + autostart agent removed.\(stateNote)")
    }

    /// Dismiss the toast for a session. Invoked by the Claude Code UserPromptSubmit / SessionEnd hooks
    /// (which pass `session_id` on stdin) or manually with `--session <id>`. Fire-and-forget: if the
    /// daemon isn't running there's nothing to dismiss, so a connection failure is silently fine.
    private static func handleDismiss(_ args: [String]) {
        let session = flagValue("session", in: args)
            ?? stringValue(for: ["session_id", "session", "sessionId"], in: readStdinObjectIfAvailable())
        guard let session, !session.isEmpty else { return }
        _ = try? UnixSocketClient.send(IPCEnvelope(command: .dismiss, session: session), waitForResponse: false)
    }

    private static func handleName(_ args: [String]) {
        if args.first == "--clear" {
            handleClear()
            return
        }
        guard let name = args.first, !name.isEmpty, let tty = Terminal.currentTTY() else {
            return
        }
        let parentPID = Terminal.parentPID()
        let registration = SessionRegistration(
            tty: tty,
            name: name,
            cwd: FileManager.default.currentDirectoryPath,
            pid: Terminal.currentPID(),
            ppid: parentPID,
            terminalBundleID: Terminal.windowOwnerPID(forShellPID: parentPID)?.bundleHint
        )
        let envelope = IPCEnvelope(command: .register, registration: registration)
        sendAndPrint(envelope)
    }

    private static func handleClear() {
        guard let tty = Terminal.currentTTY() else { return }
        let envelope = IPCEnvelope(command: .unregister, tty: tty)
        sendAndPrint(envelope)
    }

    private static func handleList() {
        let envelope = IPCEnvelope(command: .list)
        let response: IPCResponse
        do {
            guard let received = try UnixSocketClient.send(envelope, waitForResponse: true) else {
                printError("No response from CLINotify helper.")
                return
            }
            response = received
        } catch {
            printError("Cannot reach CLINotify helper: \(error.localizedDescription)")
            return
        }
        guard response.ok else {
            printError(response.message ?? "List failed.")
            return
        }
        guard let sessions = response.sessions, !sessions.isEmpty else {
            print("No registered sessions.")
            return
        }
        for session in sessions {
            let cwd = session.cwd ?? "-"
            let source = session.source?.rawValue ?? "-"
            print("\(session.tty)\t\(session.name)\t\(source)\t\(cwd)")
        }
    }

    private static func handleStatus() {
        print("channel: \(AppChannel.current.rawValue)")
        if helperIsReachable() {
            print("CLINotify helper: running")
        } else {
            print("CLINotify helper: not reachable")
        }
        print("state dir: \(ApplicationPaths.applicationSupportDirectory.path)")
        print("socket: \(ApplicationPaths.socketPath)")
        print("overlays: screen toast on the primary display")
    }

    private static func handleLaunch() {
        guard let appURL = bundledAppURL() else {
            printError("Cannot locate CLINotify.app from this clinotify binary.")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [appURL.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            printError("Failed to launch helper: \(error.localizedDescription)")
            return
        }

        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if helperIsReachable() {
                print("CLINotify helper: running")
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        printError("Launched \(appURL.path), but helper IPC did not become reachable.")
    }

    private static func handleAutostart(_ args: [String]) {
        let action = args.first ?? "status"
        let channel = AppChannel.current
        let plistURL = LaunchAgent.plistURL(for: channel)
        let label = LaunchAgent.label(for: channel)
        let domain = "gui/\(getuid())"
        let domainTarget = "\(domain)/\(label)"

        switch action {
        case "on":
            guard let appURL = bundledAppURL() else {
                printError("Cannot locate CLINotify.app from this clinotify binary.")
                return
            }
            let daemonPath = appURL.appendingPathComponent("Contents/MacOS/CLINotifyApp").path
            do {
                try FileManager.default.createDirectory(
                    at: plistURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try LaunchAgent.plistXML(channel: channel, daemonExecutablePath: daemonPath)
                    .write(to: plistURL, atomically: true, encoding: .utf8)
            } catch {
                printError("Failed to write LaunchAgent plist: \(error.localizedDescription)")
                return
            }

            // Hand control to launchd. Ordering matters: (1) drop any prior registration; (2) stop the
            // manually-launched daemon and wait for it to release the single-instance flock, so the
            // managed instance can acquire it (else it self-exits and KeepAlive churns); (3) load. We
            // bootout BEFORE killing so launchd doesn't immediately relaunch the one we're killing.
            _ = runLaunchctl(["bootout", domainTarget])
            _ = runProcess("/usr/bin/pkill", ["-f", daemonPath])
            waitForDaemonExit(matching: daemonPath, timeout: 5)
            if !runLaunchctl(["bootstrap", domain, plistURL.path]) {
                _ = runLaunchctl(["load", "-w", plistURL.path]) // older API fallback
            }
            _ = runLaunchctl(["kickstart", domainTarget]) // ensure started (no-op if RunAtLoad already did)

            let deadline = Date().addingTimeInterval(6)
            while Date() < deadline {
                if helperIsReachable() {
                    print("autostart: on — \(label) loaded; the daemon starts at login and relaunches if it exits.")
                    print("plist: \(plistURL.path)")
                    print("(to fully stop it, run: \(channel.cliName) autostart off)")
                    return
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            printError("autostart: wrote \(plistURL.path) and loaded the agent, but the helper IPC did not become reachable.")

        case "off":
            LaunchAgentControl.disable(for: channel)
            print("autostart: off — \(label) removed. The daemon will no longer start automatically.")

        case "status":
            let exists = FileManager.default.fileExists(atPath: plistURL.path)
            print("autostart: \(exists ? "on" : "off") (\(label))")
            print("plist: \(plistURL.path)")

        default:
            printError("usage: \(channel.cliName) autostart [on|off|status]")
        }
    }

    /// Run `/bin/launchctl` with args; true on exit 0. launchctl is noisy on already-loaded / not-loaded
    /// states, so callers tolerate failures (the fallbacks and the final reachability check are the
    /// real success signal).
    @discardableResult
    private static func runLaunchctl(_ args: [String]) -> Bool {
        runProcess("/bin/launchctl", args)
    }

    @discardableResult
    private static func runProcess(_ path: String, _ args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Poll until no process matches `pathFragment` (the daemon binary path), up to `timeout` seconds.
    /// `pgrep` exits 1 when nothing matches, which is our "fully gone" signal.
    private static func waitForDaemonExit(matching pathFragment: String, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !runProcess("/usr/bin/pgrep", ["-f", pathFragment]) { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private static func handleLicense(_ args: [String]) {
        let manager = LicenseManager()
        switch args.first {
        case nil, "status":
            print("license: \(manager.record.state.rawValue)")
            let caps = manager.capabilities
            print("overlay (mascot animation): \(caps.mascotAnimation ? "enabled" : "disabled")")
            print("session bubble: \(caps.sessionBubble ? "enabled" : "disabled")")
            print("custom sounds: \(caps.customSounds ? "enabled" : "disabled")")
        case "activate-local":
            guard let key = positionalArgs(Array(args.dropFirst())).first, !key.isEmpty else {
                printError("Usage: clinotify license activate-local <key>")
                return
            }
            let state: LicenseState = key.uppercased().contains("LIFE") ? .lifetime : .activeSubscription
            do {
                try manager.activateCached(key: key, state: state)
                print("license: \(state.rawValue) (local). Overlay enabled; a running helper picks this up on the next event.")
            } catch {
                printError("Failed to activate license: \(error.localizedDescription)")
            }
        case "reset":
            do {
                try manager.resetToFree()
                print("license: free")
            } catch {
                printError("Failed to reset license: \(error.localizedDescription)")
            }
        default:
            print("Usage: clinotify license <status|activate-local <key>|reset>")
        }
    }

    private static func handleTest(_ args: [String]) {
        // `clinotify test [done|attention] [--label <text>] [--session <id>]`. The legacy
        // `claude-code` positional is tolerated. Parsing is unit-tested in CLIArgsTests.
        // Default session = label so two different `--label`s stack as two toasts and repeating
        // one replaces in place; `--session` overrides for explicit control.
        let invocation = CLIArgs.parseTestArgs(args)
        let event = AgentEvent(
            source: .claudeCode,
            type: invocation.type,
            tty: Terminal.currentTTY() ?? Terminal.parentTTY() ?? "manual",
            cwd: FileManager.default.currentDirectoryPath,
            session: invocation.session,
            title: invocation.label,
            senderPID: Terminal.currentPID(),
            senderPPID: Terminal.parentPID()
        )
        // Preview the real thing: forward to the daemon over IPC so it renders the same screen toast a
        // live hook produces (ADR-0002). Bypasses the registry so a test toast shows with no prior name.
        EventPresenter.present(event, bypassRegistry: true)
    }

    private static func handleSettings(_ args: [String]) {
        let store = NotificationPreferencesStore()
        if args.isEmpty {
            printSettings(store.load())
            return
        }

        switch args.first {
        case "animation":
            handleAnimationSettings(Array(args.dropFirst()), store: store)
        case "skin":
            handleSkinSettings(Array(args.dropFirst()), store: store)
        case "frame":
            handleFrameSettings(Array(args.dropFirst()), store: store)
        case "sound":
            handleSoundSettings(Array(args.dropFirst()), store: store)
        case "scale":
            handleScaleSetting(Array(args.dropFirst()), store: store)
        case "set":
            handleBooleanSetting(Array(args.dropFirst()), store: store)
        case "mute":
            handleMuteSetting(Array(args.dropFirst()))
        case "animate":
            handlePerTerminalAnimate(Array(args.dropFirst()))
        case "show":
            handleShowEffective(Array(args.dropFirst()), store: store)
        default:
            printSettingsUsage()
        }
    }

    // MARK: - Per-terminal overrides (daemon-owned via IPC)

    private static func handleMuteSetting(_ args: [String]) {
        guard let action = positionalArgs(args).first else {
            printSettingsUsage()
            return
        }
        guard let tty = ttyArgument(args) else {
            printError("No TTY for this session. Run from a terminal or pass --tty <tty>.")
            return
        }
        let value: Bool
        switch action {
        case "on": value = true
        case "off": value = false
        case "toggle": value = !(currentOverride(tty: tty)?.soundMuted ?? false)
        default:
            printSettingsUsage()
            return
        }
        let delta = SessionPreferenceOverride(soundMuted: value)
        sendAndPrint(
            IPCEnvelope(command: .setOverride, tty: tty, override: delta),
            successMessage: "Sound \(value ? "muted" : "unmuted") for \(tty)."
        )
    }

    private static func handlePerTerminalAnimate(_ args: [String]) {
        guard let action = positionalArgs(args).first else {
            printSettingsUsage()
            return
        }
        guard let tty = ttyArgument(args) else {
            printError("No TTY for this session. Run from a terminal or pass --tty <tty>.")
            return
        }
        let value: Bool
        switch action {
        case "on": value = true
        case "off": value = false
        case "toggle": value = !(currentOverride(tty: tty)?.animationEnabled ?? true)
        default:
            printSettingsUsage()
            return
        }
        let delta = SessionPreferenceOverride(animationEnabled: value)
        sendAndPrint(
            IPCEnvelope(command: .setOverride, tty: tty, override: delta),
            successMessage: "Animation \(value ? "enabled" : "disabled") for \(tty)."
        )
    }

    private static func handleShowEffective(_ args: [String], store: NotificationPreferencesStore) {
        let global = store.load()
        printSettings(global)
        guard let tty = ttyArgument(args) else { return }
        guard let override = currentOverride(tty: tty) else {
            print("per-terminal override (\(tty)): helper not reachable")
            return
        }
        let effective = override.resolved(global: global)
        print("--- effective for \(tty) ---")
        print("sound: \(effective.soundEnabled ? "on" : "off")")
        print("animation: \(effective.animationEnabled ? "on" : "off")")
        print("claude-code animation: \(effective.claudeCodeAnimation.rawValue)")
        print("claude-code bubble skin: \(effective.claudeCodeBubbleSkin.rawValue)")
        print("claude-code frame: \(effective.claudeCodeFrameSkin.rawValue)")
        print("sound id: \(effective.selectedSoundID ?? "(default)")")
    }

    private static func currentOverride(tty: String) -> SessionPreferenceOverride? {
        let response = try? UnixSocketClient.send(IPCEnvelope(command: .getOverride, tty: tty), waitForResponse: true)
        return response?.override
    }

    private static func positionalArgs(_ args: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg.hasPrefix("--") {
                // Skip the flag and its value — but a trailing valueless flag advances by 1 only,
                // so it's dropped rather than swallowing the next-loop boundary. (Mirrors parseFlags.)
                index += (index + 1 < args.count) ? 2 : 1
                continue
            }
            result.append(arg)
            index += 1
        }
        return result
    }

    private static func ttyArgument(_ args: [String]) -> String? {
        if let explicit = flagValue("tty", in: args), !explicit.isEmpty {
            return Terminal.normalizeTTY(explicit)
        }
        return Terminal.currentTTY()
    }

    private static func handleSoundSettings(_ args: [String], store: NotificationPreferencesStore) {
        let positional = positionalArgs(args)
        guard positional.first == "claude-code" else {
            printSettingsUsage()
            return
        }
        let preferences = store.load()
        let idArg = positional.count >= 2 ? positional[1] : nil

        guard let idArg else {
            let current = preferences.selectedSoundID ?? "(default)"
            print("claude-code sound: \(current)")
            print("available:")
            for entry in SoundCatalog.claudeCodeEntries {
                printCatalogEntry(entry, ownedIDs: preferences.ownedSoundIDs)
            }
            return
        }

        guard let sound = SoundID(rawValue: idArg) else {
            printSettingsUsage()
            return
        }
        guard SoundCatalog.isSoundAvailable(sound, ownedSoundIDs: preferences.ownedSoundIDs) else {
            printError("Claude Code sound '\(sound.rawValue)' is locked. Choose a free or purchased sound.")
            return
        }

        if let explicitTTY = flagValue("tty", in: args), let tty = Terminal.normalizeTTY(explicitTTY) {
            sendAndPrint(
                IPCEnvelope(command: .setOverride, tty: tty, override: SessionPreferenceOverride(selectedSoundID: sound.rawValue)),
                successMessage: "claude-code sound for \(tty): \(sound.rawValue)"
            )
            return
        }

        guard let updated = try? store.update({ $0.selectSound(sound) }) else { return }
        print("claude-code sound: \(updated.selectedSoundID ?? "(default)")")
    }

    private static func handleScaleSetting(_ args: [String], store: NotificationPreferencesStore) {
        if args.isEmpty {
            printOverlayScale(store.load())
            return
        }
        guard args.count == 1,
              let scale = overlayScaleValue(args[0]),
              let preferences = try? store.update({ $0.setOverlayScale(scale) }) else {
            printSettingsUsage()
            return
        }
        printOverlayScale(preferences)
    }

    private static func handleAnimationSettings(_ args: [String], store: NotificationPreferencesStore) {
        let positional = positionalArgs(args)
        guard positional.first == "claude-code" else {
            printSettingsUsage()
            return
        }
        if positional.count == 1 {
            let preferences = store.load()
            print("claude-code animation: \(preferences.claudeCodeAnimation.rawValue)")
            print("available:")
            for entry in AnimationCatalog.claudeCodeEntries {
                printCatalogEntry(entry, ownedIDs: preferences.ownedAnimationIDs)
            }
            return
        }

        guard positional.count == 2, let animation = ClaudeCodeAnimation(rawValue: positional[1]) else {
            printSettingsUsage()
            return
        }
        var didSelect = false
        guard let preferences = try? store.update({ didSelect = $0.selectClaudeCodeAnimation(animation) }) else {
            return
        }
        guard didSelect else {
            printError("Claude Code animation '\(animation.rawValue)' is locked. Choose a free or purchased animation.")
            return
        }
        print("claude-code animation: \(preferences.claudeCodeAnimation.rawValue)")
    }

    private static func handleSkinSettings(_ args: [String], store: NotificationPreferencesStore) {
        let positional = positionalArgs(args)
        guard positional.first == "claude-code" else {
            printSettingsUsage()
            return
        }
        if positional.count == 1 {
            let preferences = store.load()
            print("claude-code bubble skin: \(preferences.claudeCodeBubbleSkin.rawValue)")
            print("available:")
            for entry in BubbleSkinCatalog.claudeCodeEntries {
                printCatalogEntry(entry, ownedIDs: preferences.ownedBubbleSkinIDs)
            }
            return
        }

        guard positional.count == 2, let skin = OverlaySkin(rawValue: positional[1]) else {
            printSettingsUsage()
            return
        }
        var didSelect = false
        guard let preferences = try? store.update({ didSelect = $0.selectClaudeCodeBubbleSkin(skin) }) else {
            return
        }
        guard didSelect else {
            printError("Claude Code bubble skin '\(skin.rawValue)' is locked. Choose a free or purchased skin.")
            return
        }
        print("claude-code bubble skin: \(preferences.claudeCodeBubbleSkin.rawValue)")
    }

    private static func handleFrameSettings(_ args: [String], store: NotificationPreferencesStore) {
        let positional = positionalArgs(args)
        guard positional.first == "claude-code" else {
            printSettingsUsage()
            return
        }
        if positional.count == 1 {
            let preferences = store.load()
            print("claude-code frame: \(preferences.claudeCodeFrameSkin.rawValue)")
            print("available:")
            for entry in FrameCatalog.claudeCodeEntries {
                printCatalogEntry(entry, ownedIDs: preferences.ownedFrameSkinIDs)
            }
            return
        }

        guard positional.count == 2, let frame = FrameSkin(rawValue: positional[1]) else {
            printSettingsUsage()
            return
        }
        var didSelect = false
        guard let preferences = try? store.update({ didSelect = $0.selectClaudeCodeFrameSkin(frame) }) else {
            return
        }
        guard didSelect else {
            printError("Claude Code frame '\(frame.rawValue)' is locked. Choose a free or purchased frame.")
            return
        }
        print("claude-code frame: \(preferences.claudeCodeFrameSkin.rawValue)")
    }

    private static func handleBooleanSetting(_ args: [String], store: NotificationPreferencesStore) {
        guard args.count == 2, let enabled = booleanValue(args[1]) else {
            printSettingsUsage()
            return
        }
        let key = args[0]
        guard ["alerts", "animation", "sound"].contains(key) else {
            printSettingsUsage()
            return
        }
        guard let preferences = try? store.update({ preferences in
            switch key {
            case "alerts":
                preferences.globalEnabled = enabled
            case "animation":
                preferences.animationEnabled = enabled
            case "sound":
                preferences.soundEnabled = enabled
            default:
                break
            }
        }) else {
            return
        }
        printSettings(preferences)
    }

    private static func handleEvent(_ args: [String]) {
        let parsed = parseFlags(args)
        guard let sourceValue = parsed["source"],
              let source = EventSource(rawValue: sourceValue),
              let typeValue = parsed["type"],
              let type = EventType(rawValue: typeValue) else {
            return
        }

        let stdinObject = readStdinObjectIfAvailable()
        // Drop Claude Code's `idle_prompt` Notification (the "you've been idle" nag): it re-fires while
        // the user is away and would re-spawn a toast they already dismissed. Genuine needs-you/done
        // notifications are kept. See CLIArgs.isIdleNudge.
        if CLIArgs.isIdleNudge(source: source, notificationType: stringValue(for: ["notification_type"], in: stdinObject)) {
            return
        }
        let event = AgentEvent(
            source: source,
            type: type,
            tty: Terminal.parentTTY(),
            cwd: stringValue(for: ["cwd", "current_dir"], in: stdinObject) ?? FileManager.default.currentDirectoryPath,
            session: stringValue(for: ["session_id", "session", "sessionId"], in: stdinObject),
            // For Claude Code, deliberately DON'T use the Notification hook's verbose `message`
            // ("Claude is waiting for your input") as the label — the toast's presence already means
            // "needs you", so the label stays a stable identifier (project basename). See CLIArgs.eventTitle.
            title: CLIArgs.eventTitle(
                source: source,
                title: stringValue(for: ["title"], in: stdinObject),
                message: stringValue(for: ["message"], in: stdinObject)
            ),
            senderPID: Terminal.currentPID(),
            senderPPID: Terminal.parentPID()
        )
        // Draw in-terminal from this hook process (scoped to its own controlling terminal),
        // instead of asking the daemon to position a window — see ADR 0001.
        EventPresenter.present(event)
    }

    private static func handleCodexEvent(_ args: [String]) {
        let payload = args.first ?? readStdinStringIfAvailable() ?? "{}"
        var event = CodexNotifyAdapter.event(
            from: payload,
            tty: Terminal.parentTTY(),
            cwd: FileManager.default.currentDirectoryPath
        )
        event.senderPID = Terminal.currentPID()
        event.senderPPID = Terminal.parentPID()
        EventPresenter.present(event)
    }

    private static func parseFlags(_ args: [String]) -> [String: String] {
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

    private static func flagValue(_ name: String, in args: [String]) -> String? {
        parseFlags(args)[name]
    }

    private static func readStdinObjectIfAvailable() -> [String: Any] {
        guard let text = readStdinStringIfAvailable(),
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private static func readStdinStringIfAvailable() -> String? {
        guard isatty(STDIN_FILENO) == 0 else { return nil }
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func stringValue(for keys: [String], in object: [String: Any]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func booleanValue(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "on", "true", "yes", "1":
            return true
        case "off", "false", "no", "0":
            return false
        default:
            return nil
        }
    }

    private static func overlayScaleValue(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let numberText = trimmed.hasSuffix("%") ? String(trimmed.dropLast()) : trimmed
        guard let raw = Double(numberText), raw.isFinite, raw > 0 else { return nil }
        let scale = trimmed.hasSuffix("%") || raw > 5 ? raw / 100 : raw
        return NotificationPreferences.clampedOverlayScale(scale)
    }

    private static func printSettings(_ preferences: NotificationPreferences) {
        let text = """
        alerts: \(preferences.globalEnabled ? "on" : "off")
        animation: \(preferences.animationEnabled ? "on" : "off")
        sound: \(preferences.soundEnabled ? "on" : "off")
        overlay scale: \(overlayScalePercentText(preferences.overlayScale))
        claude-code animation: \(preferences.claudeCodeAnimation.rawValue)
        claude-code bubble skin: \(preferences.claudeCodeBubbleSkin.rawValue)
        claude-code frame: \(preferences.claudeCodeFrameSkin.rawValue)
        claude-code sound: \(preferences.selectedSoundID ?? "(default)")
        """
        print(text)
    }

    private static func printOverlayScale(_ preferences: NotificationPreferences) {
        print("overlay scale: \(overlayScalePercentText(preferences.overlayScale))")
        print("range: 50%-200%")
    }

    private static func overlayScalePercentText(_ scale: Double) -> String {
        "\(Int((NotificationPreferences.clampedOverlayScale(scale) * 100).rounded()))%"
    }

    private static func printCatalogEntry<ID>(_ entry: CatalogEntry<ID>, ownedIDs: Set<String>)
    where ID: RawRepresentable, ID.RawValue == String {
        let availability = entry.access == .free || ownedIDs.contains(entry.id.rawValue) ? "available" : "locked"
        print("  \(entry.id.rawValue)\t\(entry.title)\t\(entry.access.rawValue)\t\(availability)")
    }

    private static func helperIsReachable() -> Bool {
        let envelope = IPCEnvelope(command: .list)
        guard let response = try? UnixSocketClient.send(envelope, waitForResponse: true) else {
            return false
        }
        return response.ok
    }

    /// The real on-disk path of this running binary, regardless of how it was invoked (bare
    /// PATH name, relative path, or symlink). `CommandLine.arguments[0]` can be just "clinotify".
    private static func runningExecutablePath() -> String {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else {
            return CommandLine.arguments[0]
        }
        return String(cString: buffer)
    }

    private static func bundledAppURL() -> URL? {
        let executableURL = URL(fileURLWithPath: runningExecutablePath())
            .resolvingSymlinksInPath()
        let macOSDirectory = executableURL.deletingLastPathComponent()
        let contentsDirectory = macOSDirectory.deletingLastPathComponent()
        let appURL = contentsDirectory.deletingLastPathComponent()
        if appURL.pathExtension == "app",
           FileManager.default.fileExists(atPath: appURL.appendingPathComponent("Contents/MacOS/CLINotifyApp").path) {
            return appURL
        }

        let devAppURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/app/CLINotify.app")
        if FileManager.default.fileExists(atPath: devAppURL.appendingPathComponent("Contents/MacOS/CLINotifyApp").path) {
            return devAppURL
        }
        return nil
    }

    private static func sendAndPrint(_ envelope: IPCEnvelope, successMessage: String? = nil) {
        do {
            guard let response = try UnixSocketClient.send(envelope, waitForResponse: true) else {
                printError("No response from CLINotify helper.")
                return
            }
            guard response.ok else {
                printError(response.message ?? "Command failed.")
                return
            }
            print(successMessage ?? response.message ?? "OK")
        } catch {
            printError("Cannot reach CLINotify helper: \(error.localizedDescription)")
        }
    }

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data("clinotify: \(message)\n".utf8))
    }

    private static func printUsage(advanced: Bool = false) {
        let text = """
        CLINotify — desktop toasts when Claude Code or Codex finishes or needs you.

        Setup
          clinotify install               Install the CLI + Claude Code & Codex hooks
          clinotify uninstall             Remove hooks + CLI symlink + autostart agent (--purge also deletes settings/license)
          clinotify launch                Start the menu-bar app
          clinotify autostart on          Keep the app running across logout/reboot (off | status)
          clinotify status                Channel, helper state, and paths
          clinotify list                  Show registered sessions

        Try it
          clinotify test                  Fire a test "done" toast
          clinotify test attention --label "Need input"

        Skins (run with no value to list options; some are paid)
          clinotify animation [<id>]      Crab animation
          clinotify bubble [<id>]         Speech-bubble style       (alias: skin)
          clinotify sound [<id>]          Notification sound

        Tweaks
          clinotify background [on|off]   Card/panel behind the toast
          clinotify mute [on|off|toggle]  Mute this terminal's sound
          clinotify scale [50%-200%]      Toast size
          clinotify alerts [on|off]       Master on/off for all toasts
          clinotify settings              Show every effective setting
          clinotify license [status|activate-local <key>|reset]

        Run `clinotify help --all` for hook/advanced commands.
        """
        print(text)
        guard advanced else { return }
        let advancedText = """

        Advanced / hook plumbing (installed automatically; you rarely run these by hand)
          clinotify event --source <claude_code|codex> --type <done|attention>
          clinotify codex-event '<json>'
          clinotify dismiss [--session <id>]
          clinotify name "<name>" | clinotify name --clear
          clinotify stop
          clinotify settings set <alerts|animation|sound> <on|off>
          clinotify settings <animation|skin|frame|sound> claude-code [<id>] [--tty <tty>]
          clinotify settings animate <on|off|toggle> [--tty <tty>]
          clinotify settings show [--tty <tty>]
        """
        print(advancedText)
    }

    private static func printSettingsUsage() {
        let text = """
        Usage:
          clinotify settings
          clinotify settings set <alerts|animation|sound> <on|off>
          clinotify settings scale
          clinotify settings scale <50%-200%>
          clinotify settings animation claude-code
          clinotify settings animation claude-code <right-hand-wave|squint-leg-wave>
          clinotify settings skin claude-code
          clinotify settings skin claude-code <windows-xp|classic-pixel>
          clinotify settings frame claude-code
          clinotify settings frame claude-code <panel|none>
          clinotify settings sound claude-code
          clinotify settings sound claude-code <glass|ping|submarine|arcade-chime> [--tty <tty>]
          clinotify settings mute <on|off|toggle> [--tty <tty>]
          clinotify settings animate <on|off|toggle> [--tty <tty>]
          clinotify settings show [--tty <tty>]
        """
        print(text)
    }

}
