import Combine
import Foundation

public struct AgentSession: Identifiable, Equatable, Sendable {
    public let id: String
    public let agent: String
    public let session: String
    public var state: AgentState
    public var title: String?
    public var project: String?
    public var message: String?
    public var appPath: String?
    public var appPid: Int32?
    /// Last state change.
    public var since: Date
    /// Last event of any kind.
    public var lastSeen: Date
    /// The sender's `at` on the newest event applied. Hooks run as separate processes,
    /// so events can arrive out of order; an older-stamped one must not override a newer state.
    public var lastEventAt: Date?
}

@MainActor
public final class AgentSessionStore: ObservableObject {
    public static let needsInputExpiry: TimeInterval = 600
    public static let attentionExpiry: TimeInterval = 1800
    /// A `working` row with no events for this long is assumed interrupted.
    public static let workingExpiry: TimeInterval = 1800
    public static let pruneAfter: TimeInterval = 43_200

    /// Sorted: priority descending, then `since` descending.
    @Published public private(set) var sessions: [AgentSession] = []
    /// Incremented on each transition into `needsPermission`.
    @Published public private(set) var attentionPulse: Int = 0
    @Published public private(set) var lastDoneAt: Date?
    /// Set by the app when the socket server could not start.
    @Published public var serverError: String?

    public init() {}

    public func apply(_ event: AgentEvent, now: Date = .now) {
        let id = "\(event.agent):\(event.session)"
        let index = sessions.firstIndex { $0.id == id }

        if event.state == .ended {
            if let index { sessions.remove(at: index) }
            return
        }

        if let index, let at = event.at, let newest = sessions[index].lastEventAt, at < newest {
            // Stale: a newer event already set this row's state.
            sessions[index].lastSeen = now
            if let title = event.title { sessions[index].title = title }
            if let project = event.project { sessions[index].project = project }
            if let appPath = event.appPath { sessions[index].appPath = appPath }
            if let appPid = event.appPid { sessions[index].appPid = appPid }
            return
        }

        if event.state == .needsPermission && sessions.first(where: { $0.id == id })?.state != .needsPermission {
            attentionPulse += 1
        }
        if event.state == .done { lastDoneAt = now }

        if let index {
            var row = sessions[index]
            if row.state != event.state {
                row.state = event.state
                row.since = now
            }
            row.lastSeen = now
            if let title = event.title { row.title = title }
            if let project = event.project { row.project = project }
            row.message = event.message
            if let appPath = event.appPath { row.appPath = appPath }
            if let appPid = event.appPid { row.appPid = appPid }
            if let at = event.at { row.lastEventAt = at }
            sessions[index] = row
        } else {
            sessions.append(AgentSession(
                id: id, agent: event.agent, session: event.session, state: event.state,
                title: event.title, project: event.project, message: event.message,
                appPath: event.appPath, appPid: event.appPid,
                since: now, lastSeen: now, lastEventAt: event.at))
        }
        sortSessions()
    }

    public func expire(now: Date = .now) {
        sessions.removeAll { now.timeIntervalSince($0.lastSeen) > Self.pruneAfter }
        for index in sessions.indices {
            let age = now.timeIntervalSince(sessions[index].lastSeen)
            let limit: TimeInterval?
            switch sessions[index].state {
            case .needsInput: limit = Self.needsInputExpiry
            case .needsPermission, .error: limit = Self.attentionExpiry
            case .working: limit = Self.workingExpiry
            default: limit = nil
            }
            if let limit, age > limit {
                sessions[index].state = .idle
                sessions[index].since = now
            }
        }
        sortSessions()
    }

    public func dismiss(_ id: String) {
        sessions.removeAll { $0.id == id }
    }

    public func clearFinished() {
        sessions.removeAll { $0.state == .done }
    }

    public func clearAll() {
        sessions = []
    }

    public var mood: AgentState? {
        sessions.map(\.state).max { $0.priority < $1.priority }
    }

    /// True when any session is working, even if a higher-priority state sets the mood.
    public var anyWorking: Bool { sessions.contains { $0.state == .working } }

    public var needsYouCount: Int { sessions.filter { $0.state.isHardAttention }.count }
    public var waitingCount: Int { sessions.filter { $0.state == .needsInput }.count }

    private func sortSessions() {
        sessions.sort {
            if $0.state.priority != $1.state.priority { return $0.state.priority > $1.state.priority }
            return $0.since > $1.since
        }
    }
}
