import Foundation

/// Whether a session's card can bring its app forward, and with which bundle.
public enum AppOpenDecision: Equatable, Sendable {
    case none
    case open(bundlePath: String)
}

public enum AppOpenPolicy {
    /// Opens by bundle path whenever the bundle is still on disk. The pid is
    /// ignored on purpose: if that process is gone, opening the bundle launches
    /// or fronts the app anyway. `bundleExists` is injected so the rule is testable.
    public static func decide(appPath: String?, appPid: Int32?, bundleExists: (String) -> Bool) -> AppOpenDecision {
        guard let appPath, !appPath.isEmpty, bundleExists(appPath) else { return .none }
        return .open(bundlePath: appPath)
    }
}
