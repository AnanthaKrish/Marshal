import Foundation

public enum UsageParsing {
    public static func claude(_ data: Data, now: Date = .now) -> UsageSample? {
        guard data.count <= 1_048_576,
              let payload = try? JSONDecoder().decode(ClaudePayload.self, from: data),
              !payload.session_id.isEmpty else { return nil }
        let c = payload.context_window
        let context = c?.used_percentage.flatMap { percent -> ContextUsage? in
            guard percent.isFinite, (0...100).contains(percent) else { return nil }
            let capacity = c?.context_window_size.flatMap { (1...1_000_000_000).contains($0) ? $0 : nil }
            return ContextUsage(usedPercent: percent, capacity: capacity, updatedAt: now)
        }
        let windows = payload.rate_limits.map { limits in
            [window(limits.five_hour, id: "5h", title: "5h"),
             window(limits.seven_day, id: "weekly", title: "Weekly"),
             window(limits.spend_limit, id: "spend", title: "Spend")].compactMap { $0 }
        }
        return UsageSample(agent: "claude-code", session: payload.session_id,
                           context: context, windows: windows, updatedAt: now)
    }

    public static func codexLimits(_ result: Data, now: Date = .now) -> UsageSample? {
        guard let response = try? JSONDecoder().decode(CodexLimitsResponse.self, from: result) else { return nil }
        let multiple = response.rateLimitsByLimitId?.sorted { $0.key < $1.key }.map(\.value) ?? []
        let buckets = multiple.isEmpty ? response.rateLimits.map { [$0] } ?? [] : multiple
        var windows: [UsageWindow] = []
        for (index, bucket) in buckets.enumerated() {
            let prefix = bucket.limitId ?? "codex-\(index)"
            for (name, value) in [("primary", bucket.primary), ("secondary", bucket.secondary)] {
                guard let value, let percent = value.usedPercent, percent.isFinite, (0...100).contains(percent) else { continue }
                let duration = UsageWindow.title(minutes: value.windowDurationMins)
                let title = buckets.count > 1 && prefix != "codex" ? "\(bucket.limitName ?? prefix) · \(duration)" : duration
                windows.append(UsageWindow(id: "\(prefix):\(name)", title: title, usedPercent: percent,
                                           resetsAt: value.resetsAt.map(Date.init(timeIntervalSince1970:))))
            }
        }
        return UsageSample(agent: "codex", windows: windows, updatedAt: now)
    }

    /// Decode only a token_count record, never conversation/tool content. The last
    /// request's usage is the context estimate; lifetime totals are NOT context size.
    public static func codexRecord(_ data: Data, session: String) -> UsageSample? {
        guard data.count <= 65536,
              let record = try? JSONDecoder().decode(CodexRecord.self, from: data),
              record.type == "event_msg", record.payload?.type == "token_count",
              let timestamp = record.timestamp.flatMap(AgentEvent.parseDate) else { return nil }
        guard let info = record.payload?.info else { return nil }
        var context: ContextUsage?
        if let capacity = info.model_context_window, capacity > 0,
           let used = info.last_token_usage?.total_tokens, used >= 0 {
            context = ContextUsage(usedPercent: min(100, Double(used) / Double(capacity) * 100),
                                   usedTokens: used, capacity: capacity, updatedAt: timestamp, isEstimate: true)
        }
        return UsageSample(agent: "codex", session: session, context: context, updatedAt: timestamp)
    }

    private static func window(_ value: ClaudeWindow?, id: String, title: String) -> UsageWindow? {
        guard let value, let percent = value.used_percentage, percent.isFinite, (0...100).contains(percent) else { return nil }
        return UsageWindow(id: id, title: title, usedPercent: percent,
                           resetsAt: value.resets_at.map(Date.init(timeIntervalSince1970:)))
    }

    private struct ClaudePayload: Decodable {
        var session_id: String
        var context_window: ClaudeContext?
        var rate_limits: ClaudeLimits?
    }
    private struct ClaudeContext: Decodable {
        var used_percentage: Double?
        var context_window_size: Int?
    }
    private struct ClaudeLimits: Decodable {
        var five_hour: ClaudeWindow?
        var seven_day: ClaudeWindow?
        var spend_limit: ClaudeWindow?
    }
    private struct ClaudeWindow: Decodable { var used_percentage: Double?; var resets_at: Double? }
    private struct CodexLimitsResponse: Decodable {
        var rateLimits: CodexBucket?
        var rateLimitsByLimitId: [String: CodexBucket]?
        enum CodingKeys: String, CodingKey { case rateLimits, rateLimitsByLimitId }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard c.contains(.rateLimits) || c.contains(.rateLimitsByLimitId) else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "No rate limit fields"))
            }
            rateLimits = try c.decodeIfPresent(CodexBucket.self, forKey: .rateLimits)
            rateLimitsByLimitId = try c.decodeIfPresent([String: CodexBucket].self, forKey: .rateLimitsByLimitId)
        }
    }
    private struct CodexBucket: Decodable {
        var limitId: String?
        var limitName: String?
        var primary: CodexWindow?
        var secondary: CodexWindow?
    }
    private struct CodexWindow: Decodable {
        var usedPercent: Double?
        var windowDurationMins: Int?
        var resetsAt: Double?
    }
    private struct CodexRecord: Decodable {
        var type: String
        var timestamp: String?
        var payload: CodexTokenRecord?
        enum CodingKeys: String, CodingKey { case type, timestamp, payload }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try c.decode(String.self, forKey: .type)
            guard type == "event_msg" else { return }
            timestamp = try c.decodeIfPresent(String.self, forKey: .timestamp)
            payload = try c.decodeIfPresent(CodexTokenRecord.self, forKey: .payload)
        }
    }
    private struct CodexTokenRecord: Decodable {
        var type: String
        var info: CodexInfo?
        enum CodingKeys: String, CodingKey { case type, info }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try c.decode(String.self, forKey: .type)
            if type == "token_count" { info = try c.decodeIfPresent(CodexInfo.self, forKey: .info) }
        }
    }
    private struct CodexInfo: Decodable { var last_token_usage: TokenCount?; var model_context_window: Int? }
    private struct TokenCount: Decodable { var total_tokens: Int? }
}
