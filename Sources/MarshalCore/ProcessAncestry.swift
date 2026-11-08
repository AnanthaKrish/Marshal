import Darwin
import Foundation

/// Finds the macOS app that owns a session by walking the parent-process chain.
public enum ProcessAncestry {
    public struct OwningApp: Equatable, Sendable {
        public var bundlePath: String
        public var pid: Int32
        public init(bundlePath: String, pid: Int32) {
            self.bundlePath = bundlePath
            self.pid = pid
        }
    }

    private static let maxHops = 32
    private static let bundleMarker = ".app/Contents/MacOS/"

    /// Bundle path from an executable path, or nil: ".../Foo.app/Contents/MacOS/foo" → ".../Foo.app".
    /// When bundles nest, the innermost (last) one wins.
    public static func bundlePath(fromExecutablePath path: String) -> String? {
        guard let range = path.range(of: bundleMarker, options: .backwards) else { return nil }
        return String(path[..<path.index(range.lowerBound, offsetBy: 4)])
    }

    /// Highest `.app` ancestor of `pid` (default: this process). nil when none.
    /// `pid` itself is never considered: the CLI lives inside Marshal.app, so
    /// counting it would claim every app-less session (tmux, ssh, cron) for Marshal.
    public static func owningApp(of pid: Int32 = getpid()) -> OwningApp? {
        owningApp(startingAt: pid, parent: parentPid(of:), path: executablePath(of:))
    }

    /// The walk over an injectable process table. Begins at the parent of
    /// `pid`, stops at pid <= 1 or after `maxHops` ancestors, and returns the
    /// highest ancestor whose executable sits inside a `.app` bundle.
    static func owningApp(startingAt pid: Int32,
                          parent: (Int32) -> Int32?,
                          path: (Int32) -> String?) -> OwningApp? {
        var best: OwningApp?
        var current = parent(pid)
        for _ in 0..<maxHops {
            guard let candidate = current, candidate > 1 else { break }
            if let executable = path(candidate), let bundle = bundlePath(fromExecutablePath: executable) {
                best = OwningApp(bundlePath: bundle, pid: candidate)
            }
            current = parent(candidate)
        }
        return best
    }

    /// Only recognized persistent agent processes qualify, never a shell/hook subprocess.
    public static func sessionHost(for agent: HookAgent, of pid: Int32 = getpid()) -> SessionHost? {
        var current = parentPid(of: pid)
        for _ in 0..<maxHops {
            guard let candidate = current, candidate > 1 else { break }
            if let path = executablePath(of: candidate), isSessionExecutable(path, agent: agent),
               let startedAt = processStart(candidate) {
                return SessionHost(pid: candidate, startedAt: startedAt)
            }
            current = parentPid(of: candidate)
        }
        return nil
    }

    static func isSessionExecutable(_ path: String, agent: HookAgent) -> Bool {
        let name = (path as NSString).lastPathComponent
        switch agent {
        case .claudeCode:
            return name == "claude" || path.contains("/claude/versions/")
        case .codex:
            return name == "codex" || name == "codex-aarch64-apple-darwin" || name == "codex-x86_64-apple-darwin"
        case .cursor:
            return name == "Cursor" && path.contains(".app/Contents/MacOS/")
        }
    }

    /// nil means we cannot verify; only ESRCH/empty process information proves exit.
    public static func isRunning(_ host: SessionHost) -> Bool? {
        guard host.pid > 1, host.startedAt > 0 else { return nil }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, host.pid]
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        if result != 0 { return errno == ESRCH ? false : nil }
        guard size > 0 else { return false }
        let start = info.kp_proc.p_starttime
        return UInt64(start.tv_sec) * 1_000_000 + UInt64(start.tv_usec) == host.startedAt
    }

    private static func processStart(_ pid: Int32) -> UInt64? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_starttime
        return UInt64(start.tv_sec) * 1_000_000 + UInt64(start.tv_usec)
    }

    static func parentPid(of pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    static func executablePath(of pid: Int32) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE is a macro and not importable; it is 4 * MAXPATHLEN.
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
