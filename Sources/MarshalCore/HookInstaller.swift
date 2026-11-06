import Foundation

/// Writes Marshal's hook entries into Claude Code's settings.json and Codex's hooks.json.
///
/// Marshal's groups are always appended after existing groups and existing groups are never
/// reordered or edited: Codex records trusted hooks by file, event name and array index.
public enum HookInstaller {
    public static let marker = "/.marshal/bin/marshal"

    public enum WriteResult: Equatable { case added, alreadyPresent }

    public struct RemoveResult: Equatable {
        public var removed: Bool
        /// True when a non-Marshal group followed a removed Marshal group in some event array,
        /// so its index moved and Codex will ask to trust it again.
        public var shiftedLaterGroups: Bool

        public init(removed: Bool, shiftedLaterGroups: Bool) {
            self.removed = removed
            self.shiftedLaterGroups = shiftedLaterGroups
        }
    }

    public enum InstallError: Error { case notAJSONObject, hooksNotAnObject, eventNotAnArray }

    public static func events(for agent: HookAgent) -> [(event: String, matcher: String?)] {
        switch agent {
        case .claudeCode:
            return [("SessionStart", nil), ("UserPromptSubmit", nil), ("PreToolUse", nil),
                    ("PermissionRequest", nil),
                    ("Notification", "permission_prompt|idle_prompt|agent_needs_input"),
                    ("Stop", nil), ("StopFailure", nil), ("SessionEnd", nil)]
        case .codex:
            // Codex asks the user to trust each hook entry, so keep the list short.
            return [("UserPromptSubmit", nil), ("PreToolUse", nil),
                    ("PermissionRequest", nil), ("Stop", nil), ("SessionEnd", nil)]
        }
    }

    public static func fragment(for agent: HookAgent, shimPath: String) -> [String: Any] {
        var hooks: [String: Any] = [:]
        for (event, matcher) in events(for: agent) {
            hooks[event] = [group(event: event, matcher: matcher, agent: agent, shimPath: shimPath)]
        }
        return ["hooks": hooks]
    }

    public static func fragmentJSON(for agent: HookAgent, shimPath: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: fragment(for: agent, shimPath: shimPath),
                                                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    public static func defaultFile(for agent: HookAgent) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch agent {
        case .claudeCode: return home.appendingPathComponent(".claude/settings.json")
        case .codex: return home.appendingPathComponent(".codex/hooks.json")
        }
    }

    /// A symlinked file (e.g. dotfiles-managed) is followed: the target is read, backed up and
    /// rewritten, and the link itself is left in place.
    public static func write(agent: HookAgent, shimPath: String, into link: URL, now: Date = .now) throws -> WriteResult {
        let file = link.resolvingSymlinksInPath()
        let existed = FileManager.default.fileExists(atPath: file.path)
        var root = try readRoot(file)
        var hooks = try hooksObject(in: root)
        var changed = false
        for (event, matcher) in events(for: agent) {
            var groups: [Any] = []
            if let existing = hooks[event] {
                guard let array = existing as? [Any] else { throw InstallError.eventNotAnArray }
                groups = array
            }
            if groups.contains(where: isOurs) { continue }
            groups.append(group(event: event, matcher: matcher, agent: agent, shimPath: shimPath))
            hooks[event] = groups
            changed = true
        }
        guard changed else { return .alreadyPresent }
        root["hooks"] = hooks
        if existed { try backup(file, now: now) }
        try save(root, to: file)
        return .added
    }

    public static func remove(agent: HookAgent, from link: URL, now: Date = .now) throws -> RemoveResult {
        let file = link.resolvingSymlinksInPath()
        let none = RemoveResult(removed: false, shiftedLaterGroups: false)
        guard FileManager.default.fileExists(atPath: file.path) else { return none }
        var root = try readRoot(file)
        var hooks = try hooksObject(in: root)
        var removed = false
        var shifted = false
        for (event, value) in hooks {
            guard let groups = value as? [Any] else { continue }
            let kept = groups.filter { !isOurs($0) }
            guard kept.count != groups.count else { continue }
            removed = true
            if let firstOurs = groups.firstIndex(where: isOurs),
               groups[(firstOurs + 1)...].contains(where: { !isOurs($0) }) {
                shifted = true
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        guard removed else { return none }
        root["hooks"] = hooks
        try backup(file, now: now)
        try save(root, to: file)
        return RemoveResult(removed: true, shiftedLaterGroups: shifted)
    }

    // MARK: - Helpers

    private static func group(event: String, matcher: String?, agent: HookAgent, shimPath: String) -> [String: Any] {
        var entry: [String: Any] = ["type": "command", "command": "\(shimPath) hook \(agent.rawValue)", "async": true]
        if event != "SessionEnd" { entry["timeout"] = 5 }
        var group: [String: Any] = ["hooks": [entry]]
        if let matcher { group["matcher"] = matcher }
        return group
    }

    private static func isOurs(_ group: Any) -> Bool {
        guard let group = group as? [String: Any],
              let first = (group["hooks"] as? [Any])?.first as? [String: Any],
              let command = first["command"] as? String else { return false }
        return command.contains(marker)
    }

    private static func readRoot(_ file: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        let data = try Data(contentsOf: file)
        guard let root = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String: Any] else {
            throw InstallError.notAJSONObject
        }
        return root
    }

    private static func hooksObject(in root: [String: Any]) throws -> [String: Any] {
        guard let value = root["hooks"] else { return [:] }
        guard let hooks = value as? [String: Any] else { throw InstallError.hooksNotAnObject }
        return hooks
    }

    private static func backup(_ file: URL, now: Date) throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let target = file.deletingLastPathComponent()
            .appendingPathComponent(file.lastPathComponent + ".marshal-backup-" + formatter.string(from: now))
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: file, to: target)
    }

    private static func save(_ root: [String: Any], to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: file, options: .atomic)
    }
}
