import Foundation

/// Installs provider-specific observers without changing other hooks or their ordering.
///
/// Marshal's groups are always appended after existing groups and existing groups are never
/// reordered or edited: Codex records trusted hooks by file, event name and array index.
public enum HookInstaller {
    public static let marker = "/.marshal/bin/marshal"

    public enum WriteResult: Equatable { case added, updated, alreadyPresent }

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

    public enum InstallError: Error { case notAJSONObject, hooksNotAnObject, eventNotAnArray, unsupportedVersion }

    public static func events(for agent: HookAgent) -> [(event: String, matcher: String?)] {
        switch agent {
        case .claudeCode:
            return [("SessionStart", nil), ("UserPromptSubmit", nil), ("PreToolUse", nil),
                    ("PermissionRequest", nil), ("PostToolUse", nil), ("PostToolUseFailure", nil),
                    ("Notification", "permission_prompt|agent_needs_input"),
                    ("Stop", nil), ("StopFailure", nil), ("SessionEnd", nil)]
        case .codex:
            return [("SessionStart", nil), ("UserPromptSubmit", nil), ("PreToolUse", nil),
                    ("PermissionRequest", nil), ("PostToolUse", nil), ("Interrupt", nil),
                    ("Stop", nil), ("SessionEnd", nil)]
        case .cursor:
            // Observational events plus prompt submission; never install permission decisions.
            return [("sessionStart", nil), ("beforeSubmitPrompt", nil), ("postToolUse", nil),
                    ("postToolUseFailure", nil), ("afterAgentThought", nil), ("stop", nil), ("sessionEnd", nil)]
        }
    }

    public enum Installation: Sendable { case missing, ready, needsUpdate, unreadable }

    /// Configuration presence is not proof that events are being received.
    public static func installation(for agent: HookAgent, at file: URL? = nil) -> Installation {
        let file = file ?? defaultFile(for: agent)
        guard FileManager.default.fileExists(atPath: file.path) else { return .missing }
        do {
            let root = try readRoot(file)
            let hooks = try hooksObject(in: root)
            if agent == .cursor, root["version"] as? Int != 1 { return .unreadable }
            var anyOwned = false
            var complete = true
            for (event, _) in events(for: agent) {
                let groups = hooks[event] as? [[String: Any]] ?? []
                let entries = agent == .cursor ? groups : groups.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
                let owned = entries.filter { isOurs($0, agent: agent) }
                anyOwned = anyOwned || !owned.isEmpty
                complete = complete && owned.contains { entry in
                    guard let command = entry["command"] as? String, command.hasSuffix(" " + event) else { return false }
                    return agent == .cursor || entry["async"] as? Bool == false
                }
            }
            return complete ? .ready : anyOwned ? .needsUpdate : .missing
        } catch { return .unreadable }
    }

    public static func fragment(for agent: HookAgent, shimPath: String) -> [String: Any] {
        var hooks: [String: Any] = [:]
        for (event, matcher) in events(for: agent) {
            hooks[event] = [group(event: event, matcher: matcher, agent: agent, shimPath: shimPath)]
        }
        return agent == .cursor ? ["version": 1, "hooks": hooks] : ["hooks": hooks]
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
        case .cursor: return home.appendingPathComponent(".cursor/hooks.json")
        }
    }

    /// A symlinked file (e.g. dotfiles-managed) is followed: the target is read, backed up and
    /// rewritten, and the link itself is left in place.
    public static func write(agent: HookAgent, shimPath: String, into link: URL, now: Date = .now) throws -> WriteResult {
        let file = link.resolvingSymlinksInPath()
        let existed = FileManager.default.fileExists(atPath: file.path)
        var root = try readRoot(file)
        var hooks = try hooksObject(in: root)
        if agent == .cursor, let version = root["version"], (version as? Int) != 1 {
            throw InstallError.unsupportedVersion
        }
        var changed = agent == .cursor && root["version"] == nil
        var updated = false
        for (event, matcher) in events(for: agent) {
            var groups: [Any] = []
            if let existing = hooks[event] {
                guard let array = existing as? [Any] else { throw InstallError.eventNotAnArray }
                groups = array
            }
            var found = false
            for index in groups.indices {
                guard var existing = groups[index] as? [String: Any] else { continue }
                if agent == .cursor {
                    guard isOurs(existing, agent: agent) else { continue }
                    found = true
                    var next = existing
                    next.merge(group(event: event, matcher: matcher, agent: agent, shimPath: shimPath)) { _, new in new }
                    if !NSDictionary(dictionary: existing).isEqual(to: next) {
                        groups[index] = next; changed = true; updated = true
                    }
                } else if var entries = existing["hooks"] as? [[String: Any]] {
                    for entryIndex in entries.indices where isOurs(entries[entryIndex], agent: agent) {
                        found = true
                        var next = entries[entryIndex]
                        next.merge(handler(event: event, agent: agent, shimPath: shimPath)) { _, new in new }
                        // SessionEnd and Interrupt have special host timeout rules.
                        if event == "SessionEnd" { next["timeout"] = nil }
                        if !NSDictionary(dictionary: entries[entryIndex]).isEqual(to: next) {
                            entries[entryIndex] = next; changed = true; updated = true
                        }
                    }
                    existing["hooks"] = entries
                    // Never change a shared group's matcher for someone else's handler.
                    if !entries.isEmpty && entries.allSatisfy({ isOurs($0, agent: agent) }),
                       existing["matcher"] as? String != matcher {
                        existing["matcher"] = matcher; changed = true; updated = true
                    }
                    groups[index] = existing
                }
            }
            if !found {
                groups.append(group(event: event, matcher: matcher, agent: agent, shimPath: shimPath))
                changed = true
            }
            hooks[event] = groups
        }
        guard changed else { return .alreadyPresent }
        root["hooks"] = hooks
        if agent == .cursor { root["version"] = 1 }
        if existed { try backup(file, now: now) }
        try save(root, to: file)
        return updated ? .updated : .added
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
            var kept: [Any] = []
            var removedGroup = false
            var changedEvent = false
            for value in groups {
                guard var group = value as? [String: Any] else { kept.append(value); continue }
                if agent == .cursor {
                    if isOurs(group, agent: agent) { removed = true; changedEvent = true; removedGroup = true; continue }
                } else if let entries = group["hooks"] as? [[String: Any]] {
                    let remaining = entries.filter { !isOurs($0, agent: agent) }
                    if remaining.count != entries.count {
                        removed = true; changedEvent = true
                        if remaining.isEmpty { removedGroup = true; continue }
                        group["hooks"] = remaining
                    }
                }
                if removedGroup { shifted = true }
                kept.append(group)
            }
            if changedEvent { hooks[event] = kept.isEmpty ? nil : kept }
        }
        guard removed else { return none }
        root["hooks"] = hooks
        try backup(file, now: now)
        try save(root, to: file)
        return RemoveResult(removed: true, shiftedLaterGroups: shifted)
    }

    // MARK: - Helpers

    private static func handler(event: String, agent: HookAgent, shimPath: String) -> [String: Any] {
        // Synchronous, bounded observers preserve ordering without making policy decisions.
        var entry: [String: Any] = ["command": "\(shellQuote(shimPath)) hook \(agent.rawValue) \(event)"]
        if agent != .cursor { entry["type"] = "command"; entry["async"] = false }
        if event != "SessionEnd" { entry["timeout"] = 1 }
        return entry
    }

    private static func group(event: String, matcher: String?, agent: HookAgent, shimPath: String) -> [String: Any] {
        let entry = handler(event: event, agent: agent, shimPath: shimPath)
        if agent == .cursor { return entry }
        var group: [String: Any] = ["hooks": [entry]]
        if let matcher { group["matcher"] = matcher }
        return group
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func isOurs(_ entry: [String: Any], agent: HookAgent) -> Bool {
        guard let command = entry["command"] as? String else { return false }
        // Parse just shell words, never execute the command. Match our executable and
        // provider exactly, so removal cannot delete a neighbouring hook or shell script.
        var words: [String] = []; var word = ""; var quote: Character?; var escape = false
        for char in command {
            if escape { word.append(char); escape = false; continue }
            if char == "\\" && quote != "'" { escape = true; continue }
            if let active = quote {
                if char == active { quote = nil } else { word.append(char) }
            } else if char == "'" || char == "\"" { quote = char }
            else if char.isWhitespace {
                if !word.isEmpty { words.append(word); word = "" }
            } else { word.append(char) }
        }
        if !word.isEmpty { words.append(word) }
        guard quote == nil, !escape, words.count == 3 || words.count == 4 else { return false }
        return words[0].hasPrefix("/") && words[0].hasSuffix(marker)
            && words[1] == "hook" && words[2] == agent.rawValue
            && (words.count == 3 || words[3].allSatisfy(\.isLetter))
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
        var target = file.deletingLastPathComponent()
            .appendingPathComponent(file.lastPathComponent + ".marshal-backup-" + formatter.string(from: now))
        if FileManager.default.fileExists(atPath: target.path) {
            target = target.appendingPathExtension(UUID().uuidString)
        }
        try FileManager.default.copyItem(at: file, to: target)
    }

    private static func save(_ root: [String: Any], to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: file, options: .atomic)
    }
}
