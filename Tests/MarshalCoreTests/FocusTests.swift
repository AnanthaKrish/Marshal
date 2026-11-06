import Foundation
import Testing
@testable import MarshalCore

struct FocusTimerTests {
    private let t = Date(timeIntervalSince1970: 2_000_000)

    @Test func deadlinePauseResumeAndCompletion() {
        var timer = FocusTimer()
        timer.start(minutes: 25, now: t)
        #expect(timer.remaining(at: t.addingTimeInterval(60)) == 1440)
        timer.pause(now: t.addingTimeInterval(60))
        #expect(timer.phase == .paused)
        #expect(timer.remaining(at: t.addingTimeInterval(9000)) == 1440)
        timer.resume(now: t.addingTimeInterval(9000))
        timer.advance(now: t.addingTimeInterval(10439))
        #expect(timer.phase == .running)
        timer.advance(now: t.addingTimeInterval(10440))
        #expect(timer.phase == .completed)
        #expect(timer.completedAt == t.addingTimeInterval(10440))
        #expect(timer.progress(at: t.addingTimeInterval(20000)) == 1)
    }

    @Test func pauseAtDeadlineCompletesInsteadOfFreezingZero() {
        var timer = FocusTimer()
        timer.start(minutes: 1, now: t)
        timer.pause(now: t.addingTimeInterval(60))
        #expect(timer.phase == .completed)
        timer.resume(now: t.addingTimeInterval(100))
        #expect(timer.phase == .completed)
        timer.reset()
        #expect(timer.phase == .idle && timer.completedAt == nil)
    }

    @Test func clockRoundsUpAndDurationIsBounded() {
        #expect(FocusTimer.clockText(59.2) == "01:00")
        #expect(FocusTimer.clockText(-1) == "00:00")
        var timer = FocusTimer()
        timer.start(minutes: Int.max, now: t)
        #expect(timer.duration == 10800 && timer.isValid)
        timer.start(minutes: -1, now: t)
        #expect(timer.duration == 60)
        #expect(timer.progress(at: t.addingTimeInterval(-20)) == 0)
    }

    @Test func roundTripRunningAndPaused() throws {
        var timer = FocusTimer()
        timer.start(minutes: 45, now: t)
        for paused in [false, true] {
            if paused { timer.pause(now: t.addingTimeInterval(30)) }
            let restored = try JSONDecoder().decode(FocusTimer.self, from: JSONEncoder().encode(timer))
            #expect(restored == timer && restored.isValid)
        }
    }
}

struct NudgeEngineTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)
    private func request(_ id: String, _ kind: AttentionRequest.Kind, expires: Date? = nil) -> AttentionRequest {
        AttentionRequest(id: id, kind: kind, title: id, detail: "", expiresAt: expires)
    }

    @Test func priorityDismissalAndNewOccurrence() {
        var engine = NudgeEngine()
        let requests = [request("break", .takeBreak), request("permission", .permission), request("error", .error)]
        #expect(engine.select(requests, now: now, isQuiet: false, isFocusing: false)?.id == "error")
        engine.dismiss("error")
        #expect(engine.select(requests, now: now, isQuiet: false, isFocusing: false)?.id == "permission")
        _ = engine.select([], now: now, isQuiet: false, isFocusing: false)
        #expect(engine.select(requests, now: now, isQuiet: false, isFocusing: false)?.id == "error")
    }

    @Test func quietSuppressesAllAndExpiredCompletionsNeverReplay() {
        var engine = NudgeEngine()
        let requests = [request("finished", .agentFinished, expires: now.addingTimeInterval(8))]
        #expect(engine.select(requests, now: now, isQuiet: true, isFocusing: false) == nil)
        #expect(engine.select(requests, now: now.addingTimeInterval(8), isQuiet: false, isFocusing: false) == nil)
    }

    @Test func focusDefersBreaksButAllowsApprovalsAndCriticalVitals() {
        var engine = NudgeEngine()
        let soft = [request("break", .takeBreak), request("finished", .agentFinished)]
        #expect(engine.select(soft, now: now, isQuiet: false, isFocusing: true) == nil)
        #expect(engine.select(soft + [request("vitals", .vitals)], now: now, isQuiet: false, isFocusing: true)?.id == "vitals")
        #expect(engine.select(soft + [request("approval", .permission)], now: now, isQuiet: false, isFocusing: true)?.id == "approval")
    }
}

@MainActor
struct FocusCoordinatorTests {
    private final class Clock { var now = Date(timeIntervalSince1970: 2_000_000) }

    @Test func quietExpiresWhileTimerKeepsRunning() {
        let clock = Clock()
        let focus = FocusCoordinator(clock: { clock.now })
        focus.startFocus(minutes: 25)
        focus.quiet(forMinutes: 15)
        clock.now += 899
        focus.tick()
        #expect(focus.isQuiet && focus.countdown == "10:01")
        clock.now += 1
        focus.tick()
        #expect(!focus.isQuiet && focus.quietUntil == nil && focus.countdown == "10:00")
    }

    @Test func sleepCompletesFocusOnceWithoutBreakBacklog() {
        let clock = Clock()
        let focus = FocusCoordinator(clock: { clock.now })
        focus.startFocus(minutes: 25)
        clock.now += 7200
        focus.tick()
        #expect(focus.timer.phase == .completed && focus.nudge?.kind == .focusFinished)
        let pulse = focus.nudgePulse
        focus.tick()
        #expect(focus.nudgePulse == pulse)
        focus.dismissNudge()
        #expect(focus.nudge == nil && focus.timer.phase == .idle)
    }

    @Test func breakSnoozeToggleAndFocusDeferral() {
        let clock = Clock()
        let focus = FocusCoordinator(clock: { clock.now })
        focus.startFocus(minutes: 90)
        for _ in 0..<60 { clock.now += 60; focus.tick() }
        #expect(focus.nudge == nil)
        focus.pauseFocus()
        #expect(focus.nudge?.kind == .takeBreak)
        focus.snoozeBreak()
        #expect(focus.nudge == nil)
        for _ in 0..<10 { clock.now += 60; focus.tick() }
        #expect(focus.nudge?.kind == .takeBreak)
        focus.setBreaksEnabled(false)
        #expect(focus.nudge == nil)
        focus.setBreaksEnabled(true)
        #expect(focus.nudge == nil)
    }

    @Test func restoresRunningPausedQuietAndPreferences() throws {
        let suite = "MarshalTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = Clock()
        let first = FocusCoordinator(defaults: defaults, clock: { clock.now })
        first.startFocus(minutes: 25)
        first.quiet(forMinutes: 30)
        first.setBreaksEnabled(false)
        clock.now += 60
        let restored = FocusCoordinator(defaults: defaults, clock: { clock.now })
        #expect(restored.countdown == "24:00" && restored.isQuiet && !restored.breaksEnabled)
        restored.pauseFocus()
        clock.now += 2000
        let paused = FocusCoordinator(defaults: defaults, clock: { clock.now })
        #expect(paused.countdown == "24:00" && paused.timer.phase == .paused && !paused.isQuiet)
        paused.resumeFocus()
        clock.now += 1440
        let completed = FocusCoordinator(defaults: defaults, clock: { clock.now })
        #expect(completed.nudge?.kind == .focusFinished)
    }

    @Test func repeatedAgentEventsDoNotRepeatTheGesture() {
        let clock = Clock()
        let store = AgentSessionStore()
        let focus = FocusCoordinator(clock: { clock.now })
        let event = AgentEvent(agent: "codex", session: "one", state: .needsPermission, title: "Marshal")
        store.apply(event, now: clock.now)
        focus.update(sessions: store.sessions, conditions: [])
        let pulse = focus.nudgePulse
        clock.now += 5
        store.apply(event, now: clock.now)
        focus.update(sessions: store.sessions, conditions: [])
        #expect(focus.nudgePulse == pulse)
        focus.dismissNudge()
        focus.update(sessions: store.sessions, conditions: [])
        #expect(focus.nudge == nil && store.needsYouCount == 1)
        store.apply(AgentEvent(agent: "codex", session: "one", state: .working), now: clock.now)
        focus.update(sessions: store.sessions, conditions: [])
        clock.now += 1
        store.apply(event, now: clock.now)
        focus.update(sessions: store.sessions, conditions: [])
        #expect(focus.nudgePulse == pulse + 1)
    }

    @Test func clearFinishedKeepsActiveAndWaitingSessions() {
        let store = AgentSessionStore()
        for (index, state) in [AgentState.done, .working, .needsPermission, .needsInput, .error].enumerated() {
            store.apply(AgentEvent(agent: "codex", session: "\(index)", state: state))
        }
        store.clearFinished()
        #expect(store.sessions.count == 4)
        #expect(store.needsYouCount == 2 && store.anyWorking && store.waitingCount == 1)
    }

    @Test func approvalPreemptsCompletionAndQuietKeepsPassiveState() {
        let clock = Clock()
        let store = AgentSessionStore()
        let focus = FocusCoordinator(clock: { clock.now })
        focus.startFocus(minutes: 1)
        clock.now += 60
        store.apply(AgentEvent(agent: "codex", session: "one", state: .needsPermission), now: clock.now)
        focus.update(sessions: store.sessions, conditions: .overheated)
        #expect(focus.nudge?.kind == .permission && !focus.isCelebrating)
        focus.quiet(forMinutes: 15)
        #expect(focus.nudge == nil && focus.presentationMood == nil)
        #expect(store.needsYouCount == 1 && focus.timer.phase == .completed)
        focus.endQuiet()
        focus.dismissNudge()
        #expect(focus.nudge?.kind == .vitals)
        focus.dismissNudge()
        #expect(focus.nudge?.kind == .focusFinished)
    }

    @Test func corruptStorageFallsBackToIdle() throws {
        let suite = "MarshalTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not json".utf8), forKey: FocusCoordinator.storageKey)
        let focus = FocusCoordinator(defaults: defaults)
        #expect(focus.timer.phase == .idle && !focus.isQuiet && focus.breaksEnabled)
    }
}
