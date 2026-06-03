import Darwin
import Foundation

public enum Terminal {
    public static func currentTTY() -> String? {
        if let override = ProcessInfo.processInfo.environment["CLINOTIFY_TTY"], !override.isEmpty {
            return normalizeTTY(override)
        }
        guard let pointer = ttyname(STDIN_FILENO) else { return nil }
        return normalizeTTY(String(cString: pointer))
    }

    public static func parentTTY() -> String? {
        if let override = ProcessInfo.processInfo.environment["CLINOTIFY_TTY"], !override.isEmpty {
            return normalizeTTY(override)
        }
        return ttyForProcess(pid: getppid())
    }

    public static func ttyForProcess(pid: pid_t) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "tty=", "-p", "\(pid)"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizeTTY(raw)
        } catch {
            return nil
        }
    }

    public static func normalizeTTY(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value == "??" || value == "not a tty" {
            return nil
        }
        if value.hasPrefix("/dev/") {
            value.removeFirst("/dev/".count)
        }
        return value
    }

    // MARK: - Process identity

    public static func currentPID() -> Int32 {
        getpid()
    }

    public static func parentPID() -> Int32 {
        getppid()
    }

    /// Process executable names that identify an on-screen terminal application.
    /// Names are matched against `p_comm`, which the kernel truncates to 16 bytes.
    public static let knownTerminalProcessNames: Set<String> = [
        "Terminal",
        "iTerm2",
        "iTerm",
        "ghostty",
        "alacritty",
        "wezterm-gui",
        "wezterm",
        "kitty",
        "Hyper",
        "WarpTerminal",
        "Warp",
        "Tabby",
        "Code Helper",
        "Code",
        "Electron"
    ]

    /// Map a known terminal process name to its bundle identifier hint, when one is known.
    public static func bundleHint(forProcessName name: String) -> String? {
        switch name {
        case "Terminal": return "com.apple.Terminal"
        case "iTerm2", "iTerm": return "com.googlecode.iterm2"
        case "ghostty": return "com.mitchellh.ghostty"
        case "alacritty": return "org.alacritty"
        case "wezterm-gui", "wezterm": return "com.github.wez.wezterm"
        case "kitty": return "net.kovidgoyal.kitty"
        case "Hyper": return "co.zeit.hyper"
        case "WarpTerminal", "Warp": return "dev.warp.Warp-Stable"
        case "Tabby": return "org.tabby"
        case "Code Helper", "Code", "Electron": return "com.microsoft.VSCode"
        default: return nil
        }
    }

    /// Climb the parent-process chain from `pid` until a known terminal application is found,
    /// returning that terminal's PID plus a bundle-id hint.
    ///
    /// `lookup` returns the parent PID and executable name for a given PID; it defaults to a
    /// `sysctl(KERN_PROC_PID)` query but is injectable so the climb is testable without real
    /// processes. The depth cap guards against cycles or runaway chains.
    public static func windowOwnerPID(
        forShellPID pid: Int32,
        maxDepth: Int = 16,
        lookup: (Int32) -> (ppid: Int32, name: String)? = Terminal.sysctlProcessInfo
    ) -> (pid: Int32, bundleHint: String?)? {
        var current = pid
        var depth = 0
        while depth < maxDepth {
            guard let info = lookup(current) else { return nil }
            if knownTerminalProcessNames.contains(info.name) {
                return (current, bundleHint(forProcessName: info.name))
            }
            if info.ppid <= 1 || info.ppid == current {
                return nil
            }
            current = info.ppid
            depth += 1
        }
        return nil
    }

    /// Look up a process's parent PID and executable name via `sysctl(KERN_PROC_PID)`.
    public static func sysctlProcessInfo(_ pid: Int32) -> (ppid: Int32, name: String)? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let status = mib.withUnsafeMutableBufferPointer { buffer in
            sysctl(buffer.baseAddress, u_int(buffer.count), &info, &size, nil, 0)
        }
        guard status == 0, size > 0 else { return nil }
        let ppid = info.kp_eproc.e_ppid
        let name = withUnsafeBytes(of: info.kp_proc.p_comm) { raw -> String in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
        guard !name.isEmpty else { return nil }
        return (ppid, name)
    }
}
