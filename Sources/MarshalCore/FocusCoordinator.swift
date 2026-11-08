import Combine
import Foundation

/// Shared by both panels and the menu bar. Time is injectable for deterministic tests/renders.
@MainActor
public final class FocusCoordinator: ObservableObject {
    public static let storageKey = "marshal.focus.v1"
    @Published public private(set) var timer = FocusTimer()
    @Published public private(set) var now: Date
    @Published public private(set) var quietUntil: Date?
    @Published public private(set) var breaksEnabled = true
    @Published public private(set) var nudge: AttentionRequest?
    @Published public private(set) var nudgePulse = 0

    private let defaults: UserDefaults?
    private let clock: () -> Date
    private var engine = NudgeEngine()
    private var announced: Set<String> = []
    private var watchAnnounced: [String] = []
    private var watchRequest: AttentionRequest?
    private var nudgeShownAt: Date?
    public var dismissWatch: (() -> Void)?
    private var sessions: [AgentSession] = []
    private var conditions: VitalsConditions = []
    private var breakDue: Date
    private var lastTick: Date
    private var task: Task<Void, Never>?

    private struct Saved: Codable {
        var timer: FocusTimer
        var quietUntil: Date?
        var breaksEnabled: Bool
    }

    public init(defaults: UserDefaults? = nil, clock: @escaping () -> Date = { .now }) {
        self.defaults = defaults
        self.clock = clock
        let now = clock()
        self.now = now
        lastTick = now
        breakDue = now.addingTimeInterval(3600)
        if let data = defaults?.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            if saved.timer.isValid { timer = saved.timer }
            quietUntil = saved.quietUntil
            breaksEnabled = saved.breaksEnabled
        }
        tick()
    }

    public var isQuiet: Bool { quietUntil.map { $0 > now } ?? false }
    public var isFocusing: Bool { timer.phase == .running }
    public var countdown: String { FocusTimer.clockText(timer.remaining(at: now)) }
    public var quietMinutes: Int { max(1, Int(ceil((quietUntil?.timeIntervalSince(now) ?? 0) / 60))) }
    public var activity: ActivitySignal {
        ActivitySignal.resolve(nudge: nudge?.kind, mood: presentationMood,
                               timer: timer, isQuiet: isQuiet, now: now)
    }
    public var isCelebrating: Bool {
        nudge?.kind == .agentFinished || (nudge?.kind == .focusFinished
            && now.timeIntervalSince(timer.completedAt ?? now) < 8)
    }
    public var isWatchYawning: Bool {
        nudge?.kind == .watchGentle && now.timeIntervalSince(nudgeShownAt ?? now) < 4
    }
    public func updateWatch(_ request: AttentionRequest?) {
        watchRequest = request
        tick()
    }
    public var presentationMood: AgentState? {
        guard !isQuiet else { return nil }
        if nudge?.kind == .error { return .error }
        if nudge?.kind == .permission { return .needsPermission }
        // A dismissed urgent request remains in the list, without repeatedly demanding attention.
        if sessions.contains(where: { $0.state == .working }) { return .working }
        if sessions.contains(where: { $0.state == .needsInput }) { return .needsInput }
        return nil
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    public func stop() { task?.cancel(); task = nil }

    public func update(sessions: [AgentSession], conditions: VitalsConditions) {
        self.sessions = sessions.filter(\.isCurrent)
        self.conditions = conditions
        tick()
    }

    public func startFocus(minutes: Int) {
        timer.start(minutes: minutes, now: clock())
        changed()
    }

    public func pauseFocus() { tick(); timer.pause(now: now); changed() }
    public func resumeFocus() { timer.resume(now: clock()); changed() }
    public func endFocus() { timer.reset(); changed() }

    public func quiet(forMinutes minutes: Int) {
        quietUntil = clock().addingTimeInterval(TimeInterval(min(180, max(1, minutes)) * 60))
        changed()
    }
    public func endQuiet() { quietUntil = nil; changed() }

    public func setBreaksEnabled(_ enabled: Bool) {
        breaksEnabled = enabled
        breakDue = clock().addingTimeInterval(3600)
        changed()
    }

    public func snoozeBreak() { breakDue = clock().addingTimeInterval(600); tick() }
    public func acknowledgeBreak() { breakDue = clock().addingTimeInterval(3600); tick() }

    public func dismissNudge() {
        guard let nudge else { return }
        switch nudge.kind {
        case .focusFinished: endFocus()
        case .takeBreak: acknowledgeBreak()
        case .watchGentle, .watchFirm:
            if let dismissWatch { dismissWatch() } else { engine.dismiss(nudge.id); tick() }
        default: engine.dismiss(nudge.id); tick()
        }
    }

    public func tick() {
        now = clock()
        let previous = timer.phase
        timer.advance(now: now)
        if now.timeIntervalSince(lastTick) > 120 || (previous != .completed && timer.phase == .completed) {
            breakDue = now.addingTimeInterval(3600)
        }
        lastTick = now
        var shouldSave = previous != timer.phase
        if let until = quietUntil, now >= until { quietUntil = nil; shouldSave = true }
        if shouldSave { save() }
        let requests = requests()
        announced.formIntersection(Set(requests.map(\.id)))
        let next = engine.select(requests, now: now, isQuiet: isQuiet, isFocusing: isFocusing)
        if nudge?.id != next?.id {
            nudgeShownAt = next.map { watchAnnounced.contains($0.id) ? .distantPast : now }
        }
        if nudge != next { nudge = next }
        if let next {
            if next.kind == .watchGentle || next.kind == .watchFirm {
                if !watchAnnounced.contains(next.id) {
                    watchAnnounced.append(next.id)
                    if watchAnnounced.count > 128 { watchAnnounced.removeFirst() }
                    nudgePulse += 1
                }
            } else if announced.insert(next.id).inserted { nudgePulse += 1 }
        }
    }

    private func changed() { tick(); save() }

    private func save() {
        guard let defaults, let data = try? JSONEncoder().encode(
            Saved(timer: timer, quietUntil: quietUntil, breaksEnabled: breaksEnabled)) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func requests() -> [AttentionRequest] {
        var result: [AttentionRequest] = sessions.compactMap { session in
            let kind: AttentionRequest.Kind
            let title: String
            switch session.state {
            case .error: kind = .error; title = "An agent needs a hand"
            case .needsPermission: kind = .permission; title = "Ready for your approval"
            case .done: kind = .agentFinished; title = "An agent finished"
            default: return nil
            }
            return AttentionRequest(id: "\(session.id):\(session.state.rawValue):\(session.since.timeIntervalSince1970)",
                                    kind: kind, title: title, detail: session.title ?? session.agent,
                                    sessionID: session.id,
                                    expiresAt: kind == .agentFinished ? session.since.addingTimeInterval(8) : nil)
        }
        if conditions.contains(.overheated) || conditions.contains(.dizzy) || conditions.contains(.crying) {
            let headline = conditions.contains(.overheated) ? "Your Mac needs to cool down"
                : conditions.contains(.dizzy) ? "Memory is under pressure" : "Time to plug in your Mac"
            result.append(AttentionRequest(id: "vitals:\(headline)", kind: .vitals,
                                           title: headline, detail: "Check system health below."))
        }
        if let completed = timer.completedAt {
            result.append(AttentionRequest(id: "focus:\(completed.timeIntervalSince1970)", kind: .focusFinished,
                                           title: "Nice focus. Take a breath.", detail: "Your \(Int(timer.duration / 60))-minute session is complete."))
        }
        if breaksEnabled, now >= breakDue {
            result.append(AttentionRequest(id: "break:\(breakDue.timeIntervalSince1970)", kind: .takeBreak,
                                           title: "Let's stretch a little.", detail: "A moment away from the screen?"))
        }
        if var watchRequest {
            if isFocusing && watchRequest.kind == .watchGentle {
                watchRequest.kind = .watchFirm
                watchRequest.title = "Back to your focus?"
            }
            result.append(watchRequest)
        }
        return result
    }
}
