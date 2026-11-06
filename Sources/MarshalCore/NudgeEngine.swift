import Foundation

public struct AttentionRequest: Identifiable, Equatable, Sendable {
    public enum Kind: Int, Sendable {
        case agentFinished = 10, takeBreak = 20, focusFinished = 30
        case watchGentle = 21, watchFirm = 31
        case vitals = 40, permission = 50, error = 60
    }
    public var id: String
    public var kind: Kind
    public var title: String
    public var detail: String
    public var sessionID: String?
    public var expiresAt: Date?

    public init(id: String, kind: Kind, title: String, detail: String,
                sessionID: String? = nil, expiresAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.sessionID = sessionID
        self.expiresAt = expiresAt
    }
}

/// Snapshot arbitration: stale requests disappear rather than accumulating in a queue.
public struct NudgeEngine {
    private var dismissed: Set<String> = []
    public init() {}

    public mutating func dismiss(_ id: String) { dismissed.insert(id) }

    public mutating func select(_ requests: [AttentionRequest], now: Date,
                                isQuiet: Bool, isFocusing: Bool) -> AttentionRequest? {
        dismissed.formIntersection(Set(requests.map(\.id)))
        guard !isQuiet else { return nil }
        return requests.filter {
            !dismissed.contains($0.id) && ($0.expiresAt.map { now < $0 } ?? true)
                && !(isFocusing && ($0.kind == .agentFinished || $0.kind == .takeBreak))
        }.sorted {
            $0.kind != $1.kind ? $0.kind.rawValue > $1.kind.rawValue : $0.id < $1.id
        }.first
    }
}
