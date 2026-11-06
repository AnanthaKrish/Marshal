import Foundation
import Testing
@testable import MarshalCore

@MainActor
struct ActivitySignalTests {
    private final class Clock { var now = Date(timeIntervalSince1970: 2_000_000) }

    @Test func waitingAndWorkingUseDistinctSignals() {
        let clock = Clock()
        let agents = AgentSessionStore()
        let focus = FocusCoordinator(clock: { clock.now })
        agents.apply(AgentEvent(agent: "codex", session: "waiting", state: .needsInput), now: clock.now)
        focus.update(sessions: agents.sessions, conditions: [])
        #expect(focus.activity == .waiting)
        agents.apply(AgentEvent(agent: "codex", session: "working", state: .working), now: clock.now)
        focus.update(sessions: agents.sessions, conditions: [])
        #expect(focus.activity == .working)
    }

    @Test func approvalOverridesFocusUntilDismissed() {
        let clock = Clock()
        let agents = AgentSessionStore()
        let focus = FocusCoordinator(clock: { clock.now })
        focus.startFocus(minutes: 25)
        clock.now += 300
        agents.apply(AgentEvent(agent: "codex", session: "approval", state: .needsPermission), now: clock.now)
        focus.update(sessions: agents.sessions, conditions: [])
        #expect(focus.activity == .permission)
        focus.dismissNudge()
        #expect(focus.activity == .focus(progress: focus.timer.progress(at: clock.now), paused: false))
        #expect(agents.needsYouCount == 1)
    }

    @Test func criticalVitalsOverrideTheFocusRimToo() {
        let focus = FocusCoordinator()
        focus.startFocus(minutes: 25)
        focus.update(sessions: [], conditions: .overheated)
        #expect(focus.activity == .error)
        focus.dismissNudge()
        guard case .focus = focus.activity else { Issue.record("Dismissed vitals should reveal focus"); return }
    }

    @Test func focusCompletionKeepsItsSignalAfterTheFaceStopsCelebrating() {
        let clock = Clock()
        let agents = AgentSessionStore()
        let focus = FocusCoordinator(clock: { clock.now })
        agents.apply(AgentEvent(agent: "codex", session: "working", state: .working), now: clock.now)
        focus.update(sessions: agents.sessions, conditions: [])
        focus.startFocus(minutes: 1)
        clock.now += 60
        focus.tick()
        #expect(focus.activity == .finished && focus.isCelebrating)
        clock.now += 9
        focus.tick()
        #expect(focus.activity == .finished && !focus.isCelebrating)
        focus.dismissNudge()
        #expect(focus.activity == .working)
    }

    @Test func breakOverridesPausedFocusAndRestoresItWhenAcknowledged() {
        let clock = Clock()
        let focus = FocusCoordinator(clock: { clock.now })
        focus.startFocus(minutes: 90)
        for _ in 0..<60 { clock.now += 60; focus.tick() }
        focus.pauseFocus()
        #expect(focus.activity == .reminder)
        focus.acknowledgeBreak()
        #expect(focus.activity == .focus(progress: focus.timer.progress(at: clock.now), paused: true))
    }

    @Test func quietRetainsProgressOnlyForAnActiveTimer() {
        let clock = Clock()
        let focus = FocusCoordinator(clock: { clock.now })
        focus.startFocus(minutes: 1)
        clock.now += 30
        focus.quiet(forMinutes: 15)
        #expect(focus.activity == .quiet(focusProgress: 0.5))
        clock.now += 30
        focus.tick()
        #expect(focus.activity == .quiet(focusProgress: nil))
        focus.endQuiet()
        #expect(focus.activity == .finished)
    }
}
