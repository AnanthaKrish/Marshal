import Combine
import Foundation

public enum UsageLevel: Sendable {
    case healthy, caution, critical, unknown
    public static func forUsedPercent(_ percent: Double?) -> Self {
        guard let percent, percent.isFinite, (0...100).contains(percent) else { return .unknown }
        return percent >= 90 ? .critical : percent >= 70 ? .caution : .healthy
    }
}

public struct UsageWindow: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var usedPercent: Double
    public var resetsAt: Date?

    public init(id: String, title: String, usedPercent: Double, resetsAt: Date? = nil) {
        self.id = id; self.title = title; self.usedPercent = usedPercent; self.resetsAt = resetsAt
    }
    public var isValid: Bool { usedPercent.isFinite && (0...100).contains(usedPercent) }
    public func hasReset(at now: Date) -> Bool { resetsAt.map { now >= $0 } ?? false }
    public static func title(minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return "Limit" }
        if minutes == 10080 { return "Weekly" }
        if minutes % 1440 == 0 { return "\(minutes / 1440)d" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }
}

public struct ContextUsage: Codable, Equatable, Sendable {
    public var usedPercent: Double
    public var usedTokens: Int?
    public var capacity: Int?
    public var updatedAt: Date
    public var isEstimate: Bool

    public init(usedPercent: Double, usedTokens: Int? = nil, capacity: Int? = nil,
                updatedAt: Date, isEstimate: Bool = false) {
        self.usedPercent = usedPercent; self.usedTokens = usedTokens; self.capacity = capacity
        self.updatedAt = updatedAt; self.isEstimate = isEstimate
    }
    public var isValid: Bool { usedPercent.isFinite && (0...100).contains(usedPercent) }
    public func isStale(at now: Date) -> Bool { now.timeIntervalSince(updatedAt) > 900 }
}

/// Only usage metadata crosses this boundary. No prompt, message or credential fields.
public struct UsageSample: Codable, Equatable, Sendable {
    public var agent: String
    public var session: String?
    public var context: ContextUsage?
    /// nil means this source did not report limits; [] means a successful query returned none.
    public var windows: [UsageWindow]?
    public var updatedAt: Date
    public init(agent: String, session: String? = nil, context: ContextUsage? = nil,
                windows: [UsageWindow]? = nil, updatedAt: Date) {
        self.agent = agent; self.session = session; self.context = context
        self.windows = windows; self.updatedAt = updatedAt
    }
}

public struct ProviderUsage: Equatable, Sendable {
    public var windows: [UsageWindow]
    public var updatedAt: Date
    public func isStale(at now: Date) -> Bool { now.timeIntervalSince(updatedAt) > 300 }
}

@MainActor
public final class UsageStore: ObservableObject {
    @Published public private(set) var providers: [String: ProviderUsage] = [:]
    @Published public private(set) var contexts: [String: ContextUsage] = [:]
    @Published public private(set) var messages: [String: String] = [:]
    @Published public var isRefreshing = false
    private var contextDates: [String: Date] = [:]
    public init() {}

    public func apply(_ sample: UsageSample, now: Date = .now) {
        guard HookAgent(rawValue: sample.agent) != nil,
              sample.updatedAt <= now.addingTimeInterval(60),
              now.timeIntervalSince(sample.updatedAt) <= 86400 else { return }
        if let session = sample.session {
            let key = "\(sample.agent):\(session)"
            if contextDates[key].map({ sample.updatedAt >= $0 }) ?? true {
                contextDates[key] = sample.updatedAt
                contexts[key] = sample.context.flatMap { $0.isValid ? $0 : nil }
            }
        }
        if let windows = sample.windows,
           providers[sample.agent].map({ sample.updatedAt >= $0.updatedAt }) ?? true {
            providers[sample.agent] = ProviderUsage(windows: windows.filter(\.isValid), updatedAt: sample.updatedAt)
            messages[sample.agent] = windows.isEmpty ? "No limits reported for this account" : nil
        }
    }

    public func setMessage(_ message: String?, for agent: String) { messages[agent] = message }

    public func prune(now: Date) {
        for (key, date) in contextDates where now.timeIntervalSince(date) > 86400 {
            contexts.removeValue(forKey: key); contextDates.removeValue(forKey: key)
        }
    }
}
