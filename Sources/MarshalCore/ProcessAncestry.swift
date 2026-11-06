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
