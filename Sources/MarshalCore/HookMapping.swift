import Foundation

public enum HookAgent: String, CaseIterable, Sendable {
    case claudeCode = "claude-code"
    case codex
}

/// The only fields Marshal reads from a hook payload. Prompts, responses and
/// transcripts are deliberately never decoded.
public struct HookPayload: Decodable, Sendable {
    public var sessionId: String
    public var cwd: String?
    public var hookEventName: String
    public var notificationType: String?
    public var toolName: String?
    public var sessionTitle: String?
    public var error: String?

    public init(sessionId: String, cwd: String? = nil, hookEventName: String,
                notificationType: String? = nil, toolName: String? = nil,
                sessionTitle: String? = nil, error: String? = nil) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.hookEventName = hookEventName
        self.notificationType = notificationType
        self.toolName = toolName
        self.sessionTitle = sessionTitle
        self.error = error
    }

    private enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case hookEventName = "hook_event_name"
        case notificationType = "notification_type"
        case toolName = "tool_name"
        case sessionTitle = "session_title"
        case error
    }
}

public enum HookMapper {
    public static func map(agent: HookAgent, payload: HookPayload, now: Date) -> AgentEvent? {
        var message: String?
        let state: AgentState

        switch payload.hookEventName {
        case "SessionStart": state = .idle
        case "UserPromptSubmit", "PreToolUse": state = .working
        case "Stop": state = .done
        case "SessionEnd": state = .ended
        case "PermissionRequest":
            state = .needsPermission
            message = payload.toolName
        case "Notification" where agent == .claudeCode:
            switch payload.notificationType {
            case "permission_prompt": state = .needsPermission
            case "idle_prompt", "agent_needs_input": state = .needsInput
            default: return nil
            }
        case "StopFailure" where agent == .claudeCode:
            state = .error
            message = payload.error
        case "Interrupt" where agent == .codex: state = .idle
        default: return nil
        }

        return AgentEvent(agent: agent.rawValue, session: payload.sessionId, state: state,
                          title: title(for: payload), project: payload.cwd,
                          message: message, at: now)
    }

    private static func title(for payload: HookPayload) -> String? {
        if let t = payload.sessionTitle, !t.isEmpty { return t }
        guard let cwd = payload.cwd, !cwd.isEmpty else { return nil }
        let last = (cwd as NSString).lastPathComponent
        return last.isEmpty ? nil : last
    }
}
