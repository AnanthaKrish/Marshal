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
    /// Last activity transition, not the time freshness changed.
    public var since: Date
    /// Last accepted event. Rejected events never refresh this clock.
    public var lastSeen: Date
    public var lastEventAt: Date?
    public var health: SessionHealth = .current
    public var host: SessionHost? = nil
    public var turnID: String? = nil
    public var toolName: String? = nil
    var retiredTurns: [String] = []

    public var isCurrent: Bool { health == .current }
}

@MainActor
public final class AgentSessionStore: ObservableObject {
    public static let needsInputExpiry: TimeInterval = 600
    public static let attentionExpiry: TimeInterval = 1800
    public static let workingExpiry: TimeInterval = 1800
    public static let pruneAfter: TimeInterval = 43_200
    static let maxEndedSessions = 1024

    @Published public private(set) var sessions: [AgentSession] = []
    @Published public private(set) var attentionPulse: Int = 0
    @Published public private(set) var lastDoneAt: Date?
    @Published public var serverError: String?

    /// Bounded watermarks keep delayed activity from resurrecting ended sessions.
    private struct Ended { var at: Date; var receivedAt: Date }
    private var ended: [String: Ended] = [:]
    var endedSessionCount: Int { ended.count }

    public init() {}

    public func apply(_ event: AgentEvent, now: Date = .now) {
        guard !event.agent.isEmpty, !event.session.isEmpty else { return }
        // A corrupt future timestamp must not poison a session's ordering watermark.
        if let at = event.at, at > now.addingTimeInterval(300) { return }
        pruneEnded(now: now)
        let id = "\(event.agent):\(event.session)"
        let index = sessions.firstIndex { $0.id == id }
        let previous = index.map { sessions[$0] }
        // First arrival wins timestamp ties. Legacy unstamped events remain best-effort.
        if let at = event.at {
            if let latest = previous?.lastEventAt, at <= latest { return }
            if let latest = ended[id]?.at, at <= latest { return }
        }
        if let turn = event.turnID, let previous {
            if previous.retiredTurns.contains(turn) { return }
            if previous.state == .done, previous.turnID == turn,
               [.working, .needsPermission, .needsInput].contains(event.state),
               !["UserPromptSubmit", "beforeSubmitPrompt"].contains(event.eventKind ?? "") { return }
            // A delayed stop from another turn cannot close the current turn.
            if let current = previous.turnID, current != turn,
               [.done, .error, .ended].contains(event.state) { return }
        }
        // Idle reminders aren't permission requests. Late desktop notifications must
        // not turn a finished conversation back into an approval request.
        if event.eventKind == "Notification", event.state == .needsPermission {
            guard let previous, previous.state == .working || previous.state == .needsPermission else { return }
            if previous.state == .needsPermission { return }
        }

        if event.state == .ended {
            ended[id] = Ended(at: event.at ?? now, receivedAt: now)
            pruneEnded(now: now)
            if let index { sessions.remove(at: index) }
            return
        }
        ended[id] = nil

        var row = previous ?? AgentSession(id: id, agent: event.agent, session: event.session,
            state: event.state, title: nil, project: nil, message: nil, appPath: nil, appPid: nil,
            since: now, lastSeen: now, lastEventAt: nil)
        // Parallel tools may finish while a different tool is still asking permission.
        let unrelatedTool = previous?.state == .needsPermission
            && ["PreToolUse", "PostToolUse", "PostToolUseFailure"].contains(event.eventKind ?? "")
            && row.toolName != nil && event.toolName != nil && row.toolName != event.toolName
        let nextState = unrelatedTool ? row.state : event.state
        if nextState == .needsPermission && previous?.state != .needsPermission { attentionPulse += 1 }
        if nextState == .done && previous?.state != .done { lastDoneAt = now }
        if row.state != nextState || (!row.isCurrent && nextState.isHardAttention) { row.since = now }
        row.state = nextState
        row.lastSeen = now
        row.lastEventAt = event.at ?? now
        row.health = .current
        row.host = event.host
        if let turn = event.turnID, turn != row.turnID {
            if let old = row.turnID {
                row.retiredTurns.append(old)
                row.retiredTurns = Array(row.retiredTurns.suffix(16))
            }
            row.turnID = turn
        }
        if let title = event.title { row.title = title }
        if let project = event.project { row.project = project }
        if !unrelatedTool { row.message = event.message; row.toolName = event.toolName }
        if let path = event.appPath { row.appPath = path }
        if let pid = event.appPid { row.appPid = pid }
        if let index { sessions[index] = row } else { sessions.append(row) }
        sortSessions()
    }

    /// Missing events imply uncertainty. Only a verified host exit implies disconnection.
    public func expire(now: Date = .now, isHostRunning: (SessionHost) -> Bool? = ProcessAncestry.isRunning) {
        pruneEnded(now: now)
        sessions.removeAll { now.timeIntervalSince($0.lastSeen) > Self.pruneAfter }
        for index in sessions.indices {
            let row = sessions[index]
            if row.health == .disconnected { continue }
            if let host = row.host, isHostRunning(host) == false {
                sessions[index].health = .disconnected
                continue
            }
            let limit = row.state == .needsInput ? Self.needsInputExpiry
                : row.state.isHardAttention ? Self.attentionExpiry : Self.workingExpiry
            // Unrelated activity cannot indefinitely renew an old approval request.
            let lastRelevant = row.state.isHardAttention ? row.since : row.lastSeen
            if now.timeIntervalSince(lastRelevant) > limit { sessions[index].health = .stale }
        }
        sortSessions()
    }

    public func dismiss(_ id: String) { sessions.removeAll { $0.id == id } }
    public func clearFinished() { sessions.removeAll { $0.state == .done } }
    public func clearAll() { sessions = [] }
    public var currentSessions: [AgentSession] { sessions.filter(\.isCurrent) }
    public var mood: AgentState? { currentSessions.map(\.state).max { $0.priority < $1.priority } }
    public var anyWorking: Bool { currentSessions.contains { $0.state == .working } }
    public var needsYouCount: Int { currentSessions.filter { $0.state.isHardAttention }.count }
    public var waitingCount: Int { currentSessions.filter { $0.state == .needsInput }.count }

    private func pruneEnded(now: Date) {
        ended = ended.filter { now.timeIntervalSince($0.value.receivedAt) <= Self.pruneAfter }
        if ended.count > Self.maxEndedSessions {
            for entry in ended.sorted(by: { $0.value.receivedAt < $1.value.receivedAt })
                .prefix(ended.count - Self.maxEndedSessions) { ended[entry.key] = nil }
        }
    }

    private func sortSessions() {
        sessions.sort {
            if $0.isCurrent != $1.isCurrent { return $0.isCurrent }
            if $0.state.priority != $1.state.priority { return $0.state.priority > $1.state.priority }
            if $0.since != $1.since { return $0.since > $1.since }
            return $0.id < $1.id
        }
    }
}
