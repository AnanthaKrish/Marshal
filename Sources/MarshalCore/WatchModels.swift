import Foundation

public struct WatchRule: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case site, app }
    public var kind: Kind
    public var target: String
    public var name: String
    public var enabled: Bool
    public var gentleMinutes: Int
    public var firmMinutes: Int
    public var id: String { "\(kind.rawValue):\(target)" }
    public init(kind: Kind, target: String, name: String, enabled: Bool = true,
                gentleMinutes: Int = 30, firmMinutes: Int = 45) {
        self.kind = kind; self.target = target; self.name = name; self.enabled = enabled
        self.gentleMinutes = gentleMinutes; self.firmMinutes = firmMinutes
    }
    public var isValid: Bool {
        !name.isEmpty && name.count <= 60 && target.count <= 253 &&
        (1...240).contains(gentleMinutes) && (gentleMinutes + 1...360).contains(firmMinutes) &&
        (kind == .site ? Self.domain(target) == target : !target.isEmpty && !target.contains(where: \.isWhitespace))
    }
    /// Accept pasted URLs but retain only a normalized host, never paths or queries.
    public static func domain(_ text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let parts = URLComponents(string: text.contains("://") ? text : "https://" + text),
              ["https", "http"].contains(parts.scheme ?? ""), parts.user == nil, parts.password == nil,
              let raw = parts.host else { return nil }
        let host = raw.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard host.count <= 253, labels.count >= 2,
              labels.allSatisfy({ !$0.isEmpty && $0.count <= 63 && $0.first != "-" && $0.last != "-" &&
                  $0.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 } }) else { return nil }
        return host
    }
    public static let defaults: [Self] = [
        .init(kind: .site, target: "youtube.com", name: "YouTube"),
        .init(kind: .site, target: "netflix.com", name: "Netflix"),
        .init(kind: .site, target: "primevideo.com", name: "Prime Video"),
        .init(kind: .site, target: "disneyplus.com", name: "Disney+"),
        .init(kind: .site, target: "hulu.com", name: "Hulu"),
        .init(kind: .site, target: "twitch.tv", name: "Twitch"),
        .init(kind: .site, target: "tv.apple.com", name: "Apple TV web"),
        .init(kind: .app, target: "com.apple.TV", name: "Apple TV"),
        .init(kind: .app, target: "org.videolan.vlc", name: "VLC"),
        .init(kind: .app, target: "com.colliderli.iina", name: "IINA")
    ]
}

public struct WatchSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var requiresAudio = true
    public var countInBackground = false
    public var browsers: Set<String> = []
    public var rules: [WatchRule] = WatchRule.defaults
    public init() {}
    private enum CodingKeys: String, CodingKey { case enabled, requiresAudio, countInBackground, browsers, rules }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        requiresAudio = try values.decodeIfPresent(Bool.self, forKey: .requiresAudio) ?? true
        countInBackground = try values.decodeIfPresent(Bool.self, forKey: .countInBackground) ?? false
        browsers = try values.decodeIfPresent(Set<String>.self, forKey: .browsers) ?? []
        rules = try values.decodeIfPresent([WatchRule].self, forKey: .rules) ?? WatchRule.defaults
    }
    public var isValid: Bool {
        rules.count <= 40 && rules.allSatisfy(\.isValid) &&
        Set(rules.map(\.id)).count == rules.count && browsers.count <= 10
    }
    public func match(host: String?, app: String) -> WatchRule? {
        if let host = host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) {
            return rules.filter { $0.enabled && $0.kind == .site &&
                (host == $0.target || host.hasSuffix("." + $0.target)) }
                .max { $0.target.count < $1.target.count }
        }
        return rules.first { $0.enabled && $0.kind == .app && $0.target == app }
    }
}

public struct WatchSession: Equatable, Sendable {
    public var id = UUID().uuidString
    public var ruleID: String
    public var elapsed: TimeInterval = 0
    public var lastSeen: TimeInterval
    public var snoozedUntil: TimeInterval = 0
    public var dismissedLevel = 0
}

public enum WatchText {
    /// Five-second samples must remain visible instead of looking stuck at zero minutes.
    public static func counter(_ seconds: TimeInterval) -> String {
        let total = seconds.isFinite ? Int(min(315_360_000, max(0, seconds))) : 0
        let minutes = total / 60
        let remainder = String(format: "%02d", total % 60)
        if minutes < 60 { return "\(minutes):\(remainder)" }
        return "\(minutes / 60):\(String(format: "%02d", minutes % 60)):\(remainder)"
    }
    public static func elapsed(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }
}
