import AppKit
import MarshalCore

/// Brings a session's owning app to the front.
///
/// Uses `NSWorkspace.openApplication(at:configuration:)` rather than
/// `NSRunningApplication.activate()`: the latter can be refused from a
/// non-activating panel under macOS 14's cooperative activation.
@MainActor
enum AppOpener {
    /// How long a bundle-exists answer is reused before the disk is asked again.
    /// Views ask on every render; this keeps `body` free of repeated file-system calls.
    private static let existsTTL: TimeInterval = 10
    private static var existsCache: [String: (exists: Bool, checkedAt: Date)] = [:]

    static func decision(for session: AgentSession) -> AppOpenDecision {
        AppOpenPolicy.decide(appPath: session.appPath, appPid: session.appPid, bundleExists: bundleExists)
    }

    static func canOpen(_ session: AgentSession) -> Bool {
        decision(for: session) != .none
    }

    static func open(_ session: AgentSession) {
        guard case .open(let bundlePath) = decision(for: session) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: bundlePath),
                                           configuration: configuration) { _, error in
            if let error {
                NSLog("Marshal: could not open \(bundlePath): \(error.localizedDescription)")
                // Drop the cached answer so the next render asks the disk again
                // and the card loses its Open action if the bundle is gone.
                Task { @MainActor in existsCache[bundlePath] = nil }
            }
        }
    }

    /// The bundle's file name without ".app", e.g. "Terminal".
    static func appName(for session: AgentSession) -> String? {
        guard let path = session.appPath, !path.isEmpty else { return nil }
        let name = (path as NSString).lastPathComponent
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    private static func bundleExists(_ path: String) -> Bool {
        let now = Date.now
        if let cached = existsCache[path], now.timeIntervalSince(cached.checkedAt) < existsTTL {
            return cached.exists
        }
        let exists = FileManager.default.fileExists(atPath: path)
        existsCache[path] = (exists, now)
        return exists
    }
}
