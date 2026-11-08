import Foundation

public enum AgentState: String, Codable, CaseIterable, Sendable {
    case working
    case needsPermission = "needs_permission"
    case needsInput = "needs_input"
    case done
    case error
    case idle
    case ended

    public var priority: Int {
        switch self {
        case .error: 6
        case .needsPermission: 5
        case .working: 4
        case .needsInput: 3
        case .done: 2
        case .idle: 1
        case .ended: 0
        }
    }

    public var isHardAttention: Bool {
        self == .needsPermission || self == .error
    }
}

public struct AgentEvent: Codable, Equatable, Sendable {
    public var v: Int
    public var agent: String
    public var session: String
    public var state: AgentState
    public var title: String?
    public var project: String?
    public var message: String?
    public var at: Date?
    public var appPath: String?
    public var appPid: Int32?
    public var host: SessionHost?
    public var turnID: String?
    /// Hook name only; never prompt or tool input content.
    public var eventKind: String?
    public var toolName: String?

    public init(agent: String, session: String, state: AgentState,
                title: String? = nil, project: String? = nil,
                message: String? = nil, at: Date? = nil,
                appPath: String? = nil, appPid: Int32? = nil, host: SessionHost? = nil,
                turnID: String? = nil, eventKind: String? = nil, toolName: String? = nil) {
        self.v = 1
        self.agent = agent
        self.session = session
        self.state = state
        self.title = title
        self.project = project
        self.message = message
        self.at = at
        self.appPath = appPath
        self.appPid = appPid
        self.host = host
        self.turnID = turnID
        self.eventKind = eventKind
        self.toolName = toolName
    }

    private enum CodingKeys: String, CodingKey {
        case v, agent, session, state, title, project, message, at, appPath, appPid, host, turnID, eventKind, toolName
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decodeIfPresent(Int.self, forKey: .v) ?? 1
        agent = try c.decode(String.self, forKey: .agent)
        session = try c.decode(String.self, forKey: .session)
        state = try c.decode(AgentState.self, forKey: .state)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        project = try c.decodeIfPresent(String.self, forKey: .project)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        // Lenient like `at`: an unreadable app field is dropped, never the event.
        appPath = (try? c.decodeIfPresent(String.self, forKey: .appPath)) ?? nil
        appPid = (try? c.decodeIfPresent(Int32.self, forKey: .appPid)) ?? nil
        host = try? c.decodeIfPresent(SessionHost.self, forKey: .host)
        turnID = try? c.decodeIfPresent(String.self, forKey: .turnID)
        eventKind = try? c.decodeIfPresent(String.self, forKey: .eventKind)
        toolName = try? c.decodeIfPresent(String.self, forKey: .toolName)
        // Lenient: an `at` Marshal cannot read is dropped, never the event.
        at = (try? c.decodeIfPresent(String.self, forKey: .at)).flatMap(Self.parseDate)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(v, forKey: .v)
        try c.encode(agent, forKey: .agent)
        try c.encode(session, forKey: .session)
        try c.encode(state, forKey: .state)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(project, forKey: .project)
        try c.encodeIfPresent(message, forKey: .message)
        try c.encodeIfPresent(host, forKey: .host)
        try c.encodeIfPresent(turnID, forKey: .turnID)
        try c.encodeIfPresent(eventKind, forKey: .eventKind)
        try c.encodeIfPresent(toolName, forKey: .toolName)
        try c.encodeIfPresent(at.map(Self.formatDate), forKey: .at)
        try c.encodeIfPresent(appPath, forKey: .appPath)
        try c.encodeIfPresent(appPid, forKey: .appPid)
    }

    /// ISO 8601 with or without fractional seconds (JavaScript's `toISOString()` always has them).
    static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    /// Always with milliseconds, so the store can order events fired close together.
    static func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    public static func decode(line: Data) throws -> AgentEvent {
        try JSONDecoder().decode(AgentEvent.self, from: line)
    }

    public func encodedLine() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }
}
