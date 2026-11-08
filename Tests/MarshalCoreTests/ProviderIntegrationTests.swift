import Darwin
import Foundation
import Testing
@testable import MarshalCore

struct ProviderIntegrationTests {
    private let t = Date(timeIntervalSince1970: 2_000_000)

    @Test func cursorUsesConversationIdentityAndIgnoresChatContents() throws {
        let data = Data(#"{"conversation_id":"chat-1","session_id":"alias","generation_id":"turn-2","hook_event_name":"beforeSubmitPrompt","cursor_version":"3.29.9","workspace_roots":["/work/Example"],"prompt":"PRIVATE","user_email":"PRIVATE","transcript_path":"PRIVATE","attachments":[{"content":"PRIVATE"}]}"#.utf8)
        let payload = try JSONDecoder().decode(HookPayload.self, from: data)
        let event = try #require(HookMapper.map(agent: .cursor, payload: payload, now: t))
        #expect(event.agent == "cursor" && event.session == "chat-1" && event.turnID == "turn-2")
        #expect(event.state == .working && event.project == "/work/Example" && event.title == "Example")
        #expect(!String(decoding: try event.encodedLine(), as: UTF8.self).contains("PRIVATE"))
        #expect(HookMapper.map(agent: .claudeCode, payload: payload, now: t) == nil)
    }

    @Test(arguments: ["completed", "aborted", "error", "unknown"])
    func cursorStopUsesActualOutcome(status: String) {
        let payload = HookPayload(sessionId: "c", hookEventName: "stop", status: status)
        let state = HookMapper.map(agent: .cursor, payload: payload, now: t)?.state
        let expected: AgentState? = switch status {
        case "completed": .done
        case "aborted": .idle
        case "error": .error
        default: nil
        }
        #expect(state == expected)
    }

    @Test func toolFailuresAreNotFalseAgentFailures() {
        for (agent, hook) in [(HookAgent.claudeCode, "PostToolUseFailure"), (.cursor, "postToolUseFailure")] {
            let payload = HookPayload(sessionId: "s", hookEventName: hook, error: "recoverable")
            #expect(HookMapper.map(agent: agent, payload: payload, now: t)?.state == .working)
            var interrupted = payload; interrupted.isInterrupt = true
            #expect(HookMapper.map(agent: agent, payload: interrupted, now: t)?.state == .idle)
        }
    }

    @Test func observerRepliesNeverApproveToolsOrContinueAgentTurns() throws {
        for agent in HookAgent.allCases {
            for (name, _) in HookInstaller.events(for: agent) {
                let data = Data(HookMapper.reply(agent: agent, event: name).utf8)
                let reply = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
                if agent == .cursor && name == "beforeSubmitPrompt" {
                    #expect(reply.count == 1 && reply["continue"] as? Bool == true)
                } else { #expect(reply.isEmpty) }
            }
        }
        #expect(!HookInstaller.events(for: .cursor).contains { $0.event == "preToolUse" })
    }

    @Test func boundedInputReturnsEvenWhenHostNeverClosesPipe() {
        let pipe = Pipe()
        let start = ProcessInfo.processInfo.systemUptime
        #expect(HookInput.read(fd: pipe.fileHandleForReading.fileDescriptor, timeout: 0.03) == nil)
        #expect(ProcessInfo.processInfo.systemUptime - start < 0.5)
        pipe.fileHandleForWriting.closeFile()
        pipe.fileHandleForReading.closeFile()
    }

    @Test func boundedInputAcceptsCompleteJSONAndRejectsOversize() throws {
        for limit in [4, 1024] {
            let pipe = Pipe()
            let data = Data(#"{"session_id":"s"}"#.utf8)
            try pipe.fileHandleForWriting.write(contentsOf: data)
            try pipe.fileHandleForWriting.close()
            let received = HookInput.read(fd: pipe.fileHandleForReading.fileDescriptor, maxBytes: limit)
            #expect(received == (limit == 4 ? nil : data))
            try pipe.fileHandleForReading.close()
        }
    }

    @Test func processIdentityRejectsPIDReuseAndNeverTreatsTerminalAsAgent() {
        #expect(ProcessAncestry.isRunning(SessionHost(pid: getpid(), startedAt: 1)) == false)
        #expect(ProcessAncestry.isRunning(SessionHost(pid: -1, startedAt: 1)) == nil)
        for agent in HookAgent.allCases {
            #expect(!ProcessAncestry.isSessionExecutable("/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", agent: agent))
            #expect(!ProcessAncestry.isSessionExecutable("/bin/zsh", agent: agent))
            #expect(!ProcessAncestry.isSessionExecutable("/Applications/Marshal.app/Contents/MacOS/marshal-cli", agent: agent))
        }
        #expect(ProcessAncestry.isSessionExecutable("/Users/a/.local/share/claude/versions/2.1.99", agent: .claudeCode))
        #expect(ProcessAncestry.isSessionExecutable("/Applications/Cursor.app/Contents/MacOS/Cursor", agent: .cursor))
    }

    @Test func eventMetadataRoundTripsAndOldEventsStillDecode() throws {
        let event = AgentEvent(agent: "cursor", session: "c", state: .working, at: t,
            host: SessionHost(pid: 42, startedAt: 123), turnID: "g", eventKind: "postToolUse", toolName: "Shell")
        let decoded = try AgentEvent.decode(line: event.encodedLine())
        #expect(decoded.host == event.host && decoded.turnID == "g" && decoded.toolName == "Shell")
        let legacy = try AgentEvent.decode(line: Data(#"{"agent":"codex","session":"s","state":"working"}"#.utf8))
        #expect(legacy.host == nil && legacy.turnID == nil)
    }
}

@MainActor
struct ProviderLifecycleTests {
    @Test(arguments: [HookAgent.claudeCode, .codex])
    func approvalRunCompletionClearsEveryAttentionSurface(agent: HookAgent) throws {
        let store = AgentSessionStore()
        let time = Date(timeIntervalSince1970: 2_000_000)
        let focus = FocusCoordinator(clock: { time + 6 })
        let names = ["UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "Stop"]
        for (index, name) in names.enumerated() {
            let payload = HookPayload(sessionId: "s", hookEventName: name, toolName: "Bash")
            let event = try #require(HookMapper.map(agent: agent, payload: payload, now: time + Double(index)))
            store.apply(event, now: time + Double(index))
            focus.update(sessions: store.sessions, conditions: [])
            #expect(store.needsYouCount == (name == "PermissionRequest" ? 1 : 0))
            #expect((focus.nudge?.kind == .permission) == (name == "PermissionRequest"))
        }
        #expect(store.sessions[0].state == .done && focus.activity == .finished)
        if agent == .claudeCode {
            let reminder = HookPayload(sessionId: "s", hookEventName: "Notification", notificationType: "idle_prompt")
            #expect(HookMapper.map(agent: agent, payload: reminder, now: time + 65) == nil)
        }
    }
}
