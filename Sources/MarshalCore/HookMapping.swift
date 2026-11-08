import Foundation

public enum HookAgent: String, CaseIterable, Sendable {
    case claudeCode = "claude-code"
    case codex
    case cursor

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }
}

/// Allowlisted metadata only. Prompts, responses, tool inputs and transcripts are not decoded.
public struct HookPayload: Decodable, Sendable {
    public var sessionId: String
    public var cwd: String?
    public var hookEventName: String
    public var notificationType: String?
    public var toolName: String?
    public var sessionTitle: String?
    public var error: String?
    public var turnID: String?
    public var status: String?
    public var isInterrupt: Bool
    public var cursorVersion: String?

    public init(sessionId: String, cwd: String? = nil, hookEventName: String,
                notificationType: String? = nil, toolName: String? = nil,
                sessionTitle: String? = nil, error: String? = nil, turnID: String? = nil,
                status: String? = nil, isInterrupt: Bool = false, cursorVersion: String? = nil) {
        self.sessionId = sessionId; self.cwd = cwd; self.hookEventName = hookEventName
        self.notificationType = notificationType; self.toolName = toolName
        self.sessionTitle = sessionTitle; self.error = error; self.turnID = turnID
        self.status = status; self.isInterrupt = isInterrupt; self.cursorVersion = cursorVersion
    }

    private enum CodingKeys: String, CodingKey {
        case sessionId = "session_id", conversationID = "conversation_id", cwd
        case hookEventName = "hook_event_name", notificationType = "notification_type"
        case toolName = "tool_name", sessionTitle = "session_title", error
        case turnID = "turn_id", generationID = "generation_id", workspaceRoots = "workspace_roots"
        case status, isInterrupt = "is_interrupt", cursorVersion = "cursor_version"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decodeIfPresent(String.self, forKey: .conversationID)
            ?? c.decode(String.self, forKey: .sessionId)
        hookEventName = try c.decode(String.self, forKey: .hookEventName)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
            ?? c.decodeIfPresent([String].self, forKey: .workspaceRoots)?.first
        notificationType = try c.decodeIfPresent(String.self, forKey: .notificationType)
        toolName = try c.decodeIfPresent(String.self, forKey: .toolName)
        sessionTitle = try c.decodeIfPresent(String.self, forKey: .sessionTitle)
        error = try? c.decodeIfPresent(String.self, forKey: .error)
        turnID = try c.decodeIfPresent(String.self, forKey: .generationID)
            ?? c.decodeIfPresent(String.self, forKey: .turnID)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        isInterrupt = (try? c.decodeIfPresent(Bool.self, forKey: .isInterrupt)) ?? false
        cursorVersion = try c.decodeIfPresent(String.self, forKey: .cursorVersion)
    }
}

public enum HookMapper {
    /// Empty decisions keep host permission policies intact. Cursor prompt hooks require `continue`.
    public static func reply(agent: HookAgent, event: String?) -> String {
        agent == .cursor && event == "beforeSubmitPrompt" ? #"{"continue":true}"# : "{}"
    }

    public static func map(agent: HookAgent, payload: HookPayload, now: Date) -> AgentEvent? {
        guard !payload.sessionId.isEmpty else { return nil }
        // Cursor may import Claude hooks. Its native adapter owns these conversations.
        if agent != .cursor && payload.cursorVersion != nil { return nil }
        var message: String?
        let state: AgentState
        if agent == .cursor {
            switch payload.hookEventName {
            case "sessionStart": state = .idle
            case "beforeSubmitPrompt", "postToolUse", "afterAgentThought": state = .working
            case "postToolUseFailure": state = payload.isInterrupt ? .idle : .working
            case "sessionEnd": state = .ended
            case "stop":
                switch payload.status {
                case "completed": state = .done
                case "aborted": state = .idle; message = "Stopped"
                case "error": state = .error; message = "Agent stopped with an error"
                default: return nil
                }
            default: return nil
            }
        } else {
            switch payload.hookEventName {
            case "SessionStart": state = .idle
            case "UserPromptSubmit", "PreToolUse", "PostToolUse": state = .working
            case "PostToolUseFailure" where agent == .claudeCode:
                state = payload.isInterrupt ? .idle : .working
            case "Stop": state = .done
            case "SessionEnd": state = .ended
            case "PermissionRequest": state = .needsPermission; message = payload.toolName
            case "Notification" where agent == .claudeCode:
                switch payload.notificationType {
                case "permission_prompt": state = .needsPermission
                case "agent_needs_input": state = .needsInput
                // idle_prompt means the response finished, not an outstanding question.
                default: return nil
                }
            case "StopFailure" where agent == .claudeCode:
                state = .error; message = payload.error
            case "Interrupt" where agent == .codex: state = .idle; message = "Stopped"
            default: return nil
            }
        }
        return AgentEvent(agent: agent.rawValue, session: payload.sessionId, state: state,
            title: title(for: payload), project: payload.cwd, message: message, at: now,
            turnID: payload.turnID, eventKind: payload.hookEventName, toolName: payload.toolName)
    }

    private static func title(for payload: HookPayload) -> String? {
        if let title = payload.sessionTitle, !title.isEmpty { return title }
        guard let cwd = payload.cwd, !cwd.isEmpty else { return nil }
        let last = (cwd as NSString).lastPathComponent
        return last.isEmpty ? nil : last
    }
}
