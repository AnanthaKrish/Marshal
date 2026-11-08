import Testing
import Foundation
@testable import MarshalCore

private func payload(_ event: String, notification: String? = nil, tool: String? = nil, title: String? = nil, error: String? = nil) -> HookPayload {
    HookPayload(sessionId: "s1", cwd: "/Users/ak/Desktop/Mywork/FlowApp", hookEventName: event,
                notificationType: notification, toolName: tool, sessionTitle: title, error: error)
}
private let now = Date(timeIntervalSince1970: 1_000_000)

struct HookMappingTests {
    @Test(arguments: [HookAgent.claudeCode, .codex]) func sharedEventsMap(agent: HookAgent) {
        #expect(HookMapper.map(agent: agent, payload: payload("SessionStart"), now: now)?.state == .idle)
        #expect(HookMapper.map(agent: agent, payload: payload("UserPromptSubmit"), now: now)?.state == .working)
        #expect(HookMapper.map(agent: agent, payload: payload("PreToolUse"), now: now)?.state == .working)
        #expect(HookMapper.map(agent: agent, payload: payload("Stop"), now: now)?.state == .done)
        #expect(HookMapper.map(agent: agent, payload: payload("SessionEnd"), now: now)?.state == .ended)
    }

    @Test(arguments: [HookAgent.claudeCode, .codex]) func permissionRequestCarriesToolName(agent: HookAgent) {
        let e = HookMapper.map(agent: agent, payload: payload("PermissionRequest", tool: "Bash"), now: now)
        #expect(e?.state == .needsPermission)
        #expect(e?.message == "Bash")
    }

    @Test func claudeNotificationsMap() {
        #expect(HookMapper.map(agent: .claudeCode, payload: payload("Notification", notification: "permission_prompt"), now: now)?.state == .needsPermission)
        #expect(HookMapper.map(agent: .claudeCode, payload: payload("Notification", notification: "idle_prompt"), now: now) == nil)
        #expect(HookMapper.map(agent: .claudeCode, payload: payload("Notification", notification: "agent_needs_input"), now: now)?.state == .needsInput)
        #expect(HookMapper.map(agent: .claudeCode, payload: payload("Notification", notification: "auth_success"), now: now) == nil)
    }

    @Test func claudeStopFailureIsError() {
        let e = HookMapper.map(agent: .claudeCode, payload: payload("StopFailure", error: "rate_limit"), now: now)
        #expect(e?.state == .error)
        #expect(e?.message == "rate_limit")
    }

    @Test func codexInterruptIsIdle() {
        #expect(HookMapper.map(agent: .codex, payload: payload("Interrupt"), now: now)?.state == .idle)
        #expect(HookMapper.map(agent: .claudeCode, payload: payload("Interrupt"), now: now) == nil)
    }

    @Test func unmappedEventsReturnNil() {
        #expect(HookMapper.map(agent: .claudeCode, payload: payload("UnknownEvent"), now: now) == nil)
        #expect(HookMapper.map(agent: .codex, payload: payload("SubagentStart"), now: now) == nil)
    }

    @Test func identityAndTitleFields() {
        let e = HookMapper.map(agent: .claudeCode, payload: payload("UserPromptSubmit"), now: now)!
        #expect(e.agent == "claude-code" && e.session == "s1" && e.at == now)
        #expect(e.title == "FlowApp" && e.project == "/Users/ak/Desktop/Mywork/FlowApp")
        let titled = HookMapper.map(agent: .claudeCode, payload: payload("UserPromptSubmit", title: "Fix login"), now: now)!
        #expect(titled.title == "Fix login")
    }

    @Test func payloadDecodesSnakeCaseAndIgnoresExtras() throws {
        let json = Data(#"{"session_id":"abc","cwd":"/x","hook_event_name":"Stop","transcript_path":"/t","last_assistant_message":"secret"}"#.utf8)
        let p = try JSONDecoder().decode(HookPayload.self, from: json)
        #expect(p.sessionId == "abc" && p.hookEventName == "Stop")
    }

    /// Every event the installer registers must map to a state, or its hook fires for nothing.
    @Test(arguments: HookAgent.allCases) func everyRegisteredEventMaps(agent: HookAgent) {
        for (event, matcher) in HookInstaller.events(for: agent) {
            if event == "Notification" {
                let types = (matcher ?? "").split(separator: "|").map(String.init)
                #expect(!types.isEmpty)
                for type in types {
                    #expect(HookMapper.map(agent: agent, payload: payload(event, notification: type), now: now) != nil,
                            "\(agent.rawValue) \(event) \(type)")
                }
            } else {
                #expect(HookMapper.map(agent: agent, payload: HookPayload(sessionId: "s1", hookEventName: event, status: "completed"), now: now) != nil, "\(agent.rawValue) \(event)")
            }
        }
    }
}
