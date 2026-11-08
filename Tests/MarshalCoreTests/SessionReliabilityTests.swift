import Foundation
import Testing
@testable import MarshalCore

@MainActor
struct SessionReliabilityTests {
    let t = Date(timeIntervalSince1970: 2_000_000)
    func event(_ state: AgentState, at offset: Double, session: String = "s", turn: String? = nil,
               kind: String? = nil, tool: String? = nil, host: SessionHost? = nil) -> AgentEvent {
        AgentEvent(agent: "codex", session: session, state: state, title: "Project", at: t + offset,
                   host: host, turnID: turn, eventKind: kind, toolName: tool)
    }

    @Test func delayedEndCannotRemoveNewerActivityOrChangeMetadata() {
        let store = AgentSessionStore()
        store.apply(event(.working, at: 20), now: t + 20)
        var old = event(.ended, at: 10)
        old.title = "Wrong project"; old.appPath = "/Wrong.app"
        store.apply(old, now: t + 30)
        #expect(store.sessions.count == 1)
        #expect(store.sessions[0].lastSeen == t + 20 && store.sessions[0].title == "Project")
        #expect(store.sessions[0].appPath == nil)
    }

    @Test func endBeforeActivityPreventsResurrectionButNewerTurnCanResume() {
        let store = AgentSessionStore()
        store.apply(event(.ended, at: 20), now: t + 20)
        store.apply(event(.working, at: 10), now: t + 30)
        store.apply(event(.needsPermission, at: 20), now: t + 30)
        #expect(store.sessions.isEmpty && store.attentionPulse == 0)
        store.apply(event(.working, at: 31), now: t + 31)
        #expect(store.sessions.count == 1)
    }

    @Test func duplicateAndEqualTimestampEventsHaveNoEffects() {
        let store = AgentSessionStore()
        store.apply(event(.done, at: 10), now: t + 10)
        store.apply(event(.needsPermission, at: 10), now: t + 11)
        store.apply(event(.done, at: 10), now: t + 12)
        #expect(store.sessions[0].lastSeen == t + 10)
        store.apply(event(.done, at: 13), now: t + 13)
        #expect(store.attentionPulse == 0 && store.lastDoneAt == t + 10)
        #expect(store.sessions[0].since == t + 10)
    }

    @Test func lateEventsFromRetiredTurnsCannotReopenAttention() {
        let store = AgentSessionStore()
        store.apply(event(.working, at: 1, turn: "a"), now: t + 1)
        store.apply(event(.working, at: 2, turn: "b"), now: t + 2)
        store.apply(event(.needsPermission, at: 3, turn: "a"), now: t + 3)
        store.apply(event(.ended, at: 4, turn: "unseen-old-turn"), now: t + 4)
        #expect(store.sessions[0].turnID == "b" && store.sessions[0].state == .working)
        #expect(store.attentionPulse == 0)
    }

    @Test func completedTurnCannotReopenAttentionFromLateToolCallbacks() {
        let store = AgentSessionStore()
        store.apply(event(.done, at: 1, turn: "a"), now: t + 1)
        store.apply(event(.needsPermission, at: 2, turn: "a", kind: "PermissionRequest"), now: t + 2)
        store.apply(event(.working, at: 3, turn: "a", kind: "PostToolUse"), now: t + 3)
        #expect(store.sessions[0].state == .done && store.needsYouCount == 0)
        store.apply(event(.working, at: 4, turn: "b", kind: "UserPromptSubmit"), now: t + 4)
        #expect(store.sessions[0].state == .working)
    }

    @Test func latePermissionNotificationCannotOverrideCompletion() {
        let store = AgentSessionStore()
        store.apply(event(.done, at: 1), now: t + 1)
        store.apply(event(.needsPermission, at: 2, kind: "Notification"), now: t + 2)
        #expect(store.sessions[0].state == .done && store.needsYouCount == 0)
    }

    @Test func resolvedApprovalClearsNudgeAndUnrelatedApprovalsRemain() throws {
        let store = AgentSessionStore()
        let focus = FocusCoordinator(clock: { t + 10 })
        for session in ["s", "other"] {
            store.apply(event(.needsPermission, at: 1, session: session, kind: "PermissionRequest", tool: "Bash"), now: t + 1)
        }
        // Another parallel tool finishing cannot resolve Bash's approval.
        store.apply(event(.working, at: 2, kind: "PostToolUse", tool: "Read"), now: t + 2)
        #expect(store.needsYouCount == 2)
        store.apply(event(.working, at: 3, kind: "PostToolUse", tool: "Bash"), now: t + 3)
        focus.update(sessions: store.sessions, conditions: [])
        #expect(store.needsYouCount == 1 && focus.nudge?.sessionID == "codex:other")
        store.apply(event(.done, at: 4, session: "other"), now: t + 4)
        focus.update(sessions: store.sessions, conditions: [])
        #expect(store.needsYouCount == 0 && focus.nudge?.kind != .permission)
    }

    @Test func staleInformationIsRetainedWithoutDrivingMoodOrNudges() {
        let store = AgentSessionStore()
        let focus = FocusCoordinator(clock: { t + 1801 })
        store.apply(event(.needsPermission, at: 0), now: t)
        store.apply(event(.working, at: 0, session: "other"), now: t)
        store.expire(now: t + 1801)
        focus.update(sessions: store.sessions, conditions: [])
        #expect(store.sessions.allSatisfy { $0.health == .stale })
        #expect(store.sessions.contains { $0.state == .needsPermission })
        #expect(store.mood == nil && !store.anyWorking && store.needsYouCount == 0)
        #expect(focus.nudge == nil && focus.presentationMood == nil)
        store.apply(event(.working, at: 1802), now: t + 1802)
        store.expire(now: t + 3603)
        store.apply(event(.needsPermission, at: 0), now: t + 3604)
        #expect(store.sessions.first { $0.session == "s" }?.health == .stale)
        store.apply(event(.working, at: 3605), now: t + 3605)
        #expect(store.anyWorking && store.sessions.first?.health == .current)
    }

    @Test func disconnectedRequiresConfirmedHostExitAndRecoversOnANewEvent() {
        let host = SessionHost(pid: 987, startedAt: 123)
        let store = AgentSessionStore()
        store.apply(event(.needsPermission, at: 0, host: host), now: t)
        store.expire(now: t + 1, isHostRunning: { _ in nil })
        #expect(store.sessions[0].health == .current)
        store.expire(now: t + 2, isHostRunning: { $0 == host ? false : nil })
        #expect(store.sessions[0].health == .disconnected && store.needsYouCount == 0)
        store.apply(event(.working, at: 1), now: t + 3)
        #expect(store.sessions[0].health == .current && store.sessions[0].host == nil)
    }

    @Test func appOpeningPIDAndHookExitAreNotSessionLiveness() {
        let store = AgentSessionStore()
        var e = event(.working, at: 0)
        e.appPid = 111; e.appPath = "/Applications/Terminal.app"
        store.apply(e, now: t)
        store.expire(now: t + 1801, isHostRunning: { _ in Issue.record("No session host was recorded"); return false })
        #expect(store.sessions[0].health == .stale)
    }

    @Test func endWatermarksAreBoundedAndExpire() {
        let store = AgentSessionStore()
        for i in 0..<1100 { store.apply(event(.ended, at: 0, session: "\(i)"), now: t) }
        #expect(store.endedSessionCount == AgentSessionStore.maxEndedSessions)
        store.expire(now: t + AgentSessionStore.pruneAfter + 1)
        #expect(store.endedSessionCount == 0)
    }

    @Test func invalidFutureTimestampDoesNotPoisonSession() {
        let store = AgentSessionStore()
        store.apply(event(.needsPermission, at: 10000), now: t)
        store.apply(event(.working, at: 1), now: t + 1)
        #expect(store.sessions[0].state == .working && store.attentionPulse == 0)
    }
}
