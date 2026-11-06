import Foundation

/// Uses monotonic time; never estimates what happened across sleep or missing samples.
public struct WatchEngine {
    public private(set) var sessions: [String: WatchSession] = [:]
    public private(set) var currentRuleID: String?
    public private(set) var lastRuleID: String?
    private var lastTick: TimeInterval?
    public init() {}
    public var displayed: WatchSession? { lastRuleID.flatMap { sessions[$0] } }

    public mutating func observe(ruleID: String?, at now: TimeInterval) {
        guard now.isFinite, now >= 0 else { return }
        if let lastTick, now < lastTick { self = Self() }
        sessions = sessions.filter { now - $0.value.lastSeen <= 300 }
        if let id = ruleID {
            var session = sessions[id] ?? WatchSession(ruleID: id, lastSeen: now)
            if currentRuleID == id, let lastTick, (0...15).contains(now - lastTick) {
                session.elapsed += now - lastTick
            }
            session.lastSeen = now
            sessions[id] = session
            lastRuleID = id
        }
        currentRuleID = ruleID
        lastTick = now
    }
    public mutating func retainRules(_ ids: Set<String>) {
        sessions = sessions.filter { ids.contains($0.key) }
        if let currentRuleID, !ids.contains(currentRuleID) { self.currentRuleID = nil }
        if let lastRuleID, !ids.contains(lastRuleID) { self.lastRuleID = nil }
    }
    public func request(rule: WatchRule, at now: TimeInterval) -> AttentionRequest? {
        guard currentRuleID == rule.id, let session = sessions[rule.id], now >= session.snoozedUntil else { return nil }
        let level = level(session, rule: rule)
        guard level > session.dismissedLevel else { return nil }
        return AttentionRequest(id: "watch:\(session.id):\(level)", kind: level == 2 ? .watchFirm : .watchGentle,
                                title: level == 2 ? "Time for a screen break?" : "A little breather?",
                                detail: "\(rule.name) · about \(WatchText.elapsed(session.elapsed))")
    }
    public mutating func dismiss(rule: WatchRule) {
        guard var session = sessions[rule.id] else { return }
        session.dismissedLevel = level(session, rule: rule)
        sessions[rule.id] = session
    }
    public mutating func snooze(at now: TimeInterval) {
        guard let id = lastRuleID else { return }
        sessions[id]?.snoozedUntil = now + 600
    }
    public mutating func resetCurrent() {
        if let id = lastRuleID { sessions.removeValue(forKey: id) }
        currentRuleID = nil; lastRuleID = nil; lastTick = nil
    }
    private func level(_ session: WatchSession, rule: WatchRule) -> Int {
        session.elapsed >= Double(rule.firmMinutes * 60) ? 2 :
            session.elapsed >= Double(rule.gentleMinutes * 60) ? 1 : 0
    }
}
