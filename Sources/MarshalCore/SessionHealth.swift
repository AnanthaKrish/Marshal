import Foundation

/// Freshness is independent of the agent's last reported activity.
public enum SessionHealth: String, Equatable, Sendable {
    case current, stale, disconnected

    public var label: String {
        switch self {
        case .current: "Recent update"
        case .stale: "Stale"
        case .disconnected: "Disconnected"
        }
    }
}

/// A PID alone can be recycled. Never use the app-opening target as session liveness.
public struct SessionHost: Codable, Equatable, Sendable {
    public var pid: Int32
    public var startedAt: UInt64
    public init(pid: Int32, startedAt: UInt64) {
        self.pid = pid
        self.startedAt = startedAt
    }
}
