import Foundation
import Testing
@testable import MarshalCore

private func ev(_ state: AgentState, agent: String = "claude-code", session: String = "s1", message: String? = nil) -> AgentEvent {
    AgentEvent(agent: agent, session: session, state: state, title: "FlowApp", message: message)
}
private let t0 = Date(timeIntervalSince1970: 1_000_000)

@MainActor
struct AgentSessionStoreTests {
    @Test func applyCreatesRowAndUpdatesIt() {
        let store = AgentSessionStore()
        store.apply(ev(.working), now: t0)
        #expect(store.sessions.count == 1 && store.sessions[0].id == "claude-code:s1" && store.sessions[0].since == t0)
        store.apply(ev(.working), now: t0 + 5)
        #expect(store.sessions[0].since == t0 && store.sessions[0].lastSeen == t0 + 5)
        store.apply(ev(.needsPermission, message: "Bash"), now: t0 + 9)
        #expect(store.sessions[0].since == t0 + 9 && store.sessions[0].message == "Bash")
    }

    @Test func endedRemovesRow() {
        let store = AgentSessionStore()
        store.apply(ev(.working), now: t0); store.apply(ev(.ended), now: t0 + 1)
        #expect(store.sessions.isEmpty)
    }

    @Test func sortedByPriorityThenRecency() {
        let store = AgentSessionStore()
        store.apply(ev(.working, session: "a"), now: t0)
        store.apply(ev(.needsPermission, session: "b"), now: t0 + 1)
        store.apply(ev(.working, session: "c"), now: t0 + 2)
        #expect(store.sessions.map(\.session) == ["b", "c", "a"])
    }

    @Test func moodAndCounts() {
        let store = AgentSessionStore()
        #expect(store.mood == nil)
        store.apply(ev(.needsInput, session: "a"), now: t0)
        store.apply(ev(.working, session: "b"), now: t0)
        #expect(store.mood == .working && store.waitingCount == 1 && store.needsYouCount == 0)
        store.apply(ev(.error, session: "c"), now: t0)
        #expect(store.mood == .error && store.needsYouCount == 1)
    }

    @Test func olderStampedEventDoesNotOverrideNewerState() {
        let store = AgentSessionStore()
        var permission = ev(.needsPermission, message: "Bash"); permission.at = t0 + 1.000
        var working = ev(.working); working.at = t0 + 0.990
        store.apply(permission, now: t0 + 2)
        store.apply(working, now: t0 + 3)
        #expect(store.sessions[0].state == .needsPermission && store.attentionPulse == 1)
        #expect(store.sessions[0].message == "Bash" && store.sessions[0].since == t0 + 2 && store.sessions[0].lastSeen == t0 + 3)
        store.apply(ev(.working), now: t0 + 4)   // no `at`: always applies
        #expect(store.sessions[0].state == .working)
    }

    @Test func anyWorkingIsTrueWhenAWorkingSessionIsOutranked() {
        let store = AgentSessionStore()
        #expect(!store.anyWorking)
        store.apply(ev(.working, session: "a"), now: t0)
        store.apply(ev(.needsPermission, session: "b"), now: t0)
        #expect(store.mood == .needsPermission && store.anyWorking)
        store.apply(ev(.done, session: "a"), now: t0 + 1)
        #expect(!store.anyWorking)
    }

    @Test func expiryRules() {
        let store = AgentSessionStore()
        store.apply(ev(.needsInput, session: "a"), now: t0)
        store.apply(ev(.needsPermission, session: "b"), now: t0)
        store.apply(ev(.error, session: "c"), now: t0)
        store.apply(ev(.working, session: "d"), now: t0)
        store.expire(now: t0 + 599)
        #expect(store.sessions.first { $0.session == "a" }?.state == .needsInput)
        store.expire(now: t0 + 601)
        #expect(store.sessions.first { $0.session == "a" }?.state == .idle)
        #expect(store.sessions.first { $0.session == "b" }?.state == .needsPermission)
        store.expire(now: t0 + 1801)
        #expect(store.sessions.first { $0.session == "b" }?.state == .idle)
        #expect(store.sessions.first { $0.session == "c" }?.state == .idle)
        #expect(store.sessions.first { $0.session == "d" }?.state == .idle)   // working expires too
        store.expire(now: t0 + 43_201)
        #expect(store.sessions.isEmpty)
    }

    @Test func eventResetsExpiryClock() {
        let store = AgentSessionStore()
        store.apply(ev(.needsPermission), now: t0)
        store.apply(ev(.needsPermission), now: t0 + 1000)
        store.expire(now: t0 + 1801)
        #expect(store.sessions[0].state == .needsPermission)
    }

    @Test func dismissAndClearAll() {
        let store = AgentSessionStore()
        store.apply(ev(.working, session: "a"), now: t0); store.apply(ev(.working, session: "b"), now: t0)
        store.dismiss("claude-code:a")
        #expect(store.sessions.map(\.session) == ["b"])
        store.clearAll()
        #expect(store.sessions.isEmpty)
        store.apply(ev(.working, session: "a"), now: t0 + 1)
        #expect(store.sessions.count == 1)
    }

    @Test func attentionPulseAndLastDone() {
        let store = AgentSessionStore()
        store.apply(ev(.needsPermission), now: t0)
        store.apply(ev(.needsPermission), now: t0 + 1)
        #expect(store.attentionPulse == 1)
        store.apply(ev(.working), now: t0 + 2); store.apply(ev(.needsPermission), now: t0 + 3)
        #expect(store.attentionPulse == 2)
        store.apply(ev(.done), now: t0 + 4)
        #expect(store.lastDoneAt == t0 + 4)
    }

    @Test func workingExpiresToIdleAfterThirtyMinutes() {
        let store = AgentSessionStore()
        store.apply(ev(.working), now: t0)
        store.expire(now: t0 + 1799)
        #expect(store.sessions[0].state == .working)
        store.expire(now: t0 + 1801)
        #expect(store.sessions[0].state == .idle)
        #expect(store.anyWorking == false)
    }

    @Test func appInfoIsKeptWhenLaterEventOmitsIt() {
        let store = AgentSessionStore()
        store.apply(AgentEvent(agent: "claude-code", session: "s", state: .working, appPath: "/Applications/Utilities/Terminal.app", appPid: 7), now: t0)
        store.apply(AgentEvent(agent: "claude-code", session: "s", state: .needsPermission), now: t0 + 1)
        #expect(store.sessions[0].appPath == "/Applications/Utilities/Terminal.app" && store.sessions[0].appPid == 7)
    }
}
