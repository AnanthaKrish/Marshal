import Foundation
import Testing
@testable import MarshalCore

struct HookInstallerTests {
    private func tempFile() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("hooks-\(UUID()).json") }
    private let shim = "/Users/ak/.marshal/bin/marshal"
    private func hooks(_ file: URL) throws -> [String: Any] {
        (try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any])["hooks"] as! [String: Any]
    }

    @Test func fragmentListsTheRightEvents() {
        let claude = HookInstaller.fragment(for: .claudeCode, shimPath: shim)["hooks"] as! [String: Any]
        #expect(Set(claude.keys) == ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd"])
        let codex = HookInstaller.fragment(for: .codex, shimPath: shim)["hooks"] as! [String: Any]
        #expect(Set(codex.keys) == ["UserPromptSubmit", "PreToolUse", "PermissionRequest", "Stop", "SessionEnd"])
        let notif = (claude["Notification"] as! [[String: Any]])[0]
        #expect(notif["matcher"] as? String == "permission_prompt|idle_prompt|agent_needs_input")
        let entry = ((claude["Stop"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]])[0]
        #expect(entry["command"] as? String == "\(shim) hook claude-code" && entry["async"] as? Bool == true && entry["timeout"] as? Int == 5)
        let end = ((claude["SessionEnd"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]])[0]
        #expect(end["timeout"] == nil)
        for agent in HookAgent.allCases {
            let json = HookInstaller.fragmentJSON(for: agent, shimPath: shim)
            #expect(json.contains("/.marshal/bin/marshal") && !json.contains("\\/"))
        }
    }

    private func writeLegacySevenHookFile() throws -> URL {
        let file = tempFile()
        var hooks: [String: Any] = [:]
        for event in ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "Stop", "Interrupt", "SessionEnd"] {
            var entry: [String: Any] = ["type": "command", "command": "\(shim) hook codex", "async": true]
            if event != "SessionEnd" { entry["timeout"] = 5 }
            hooks[event] = [["hooks": [entry]]]
        }
        try JSONSerialization.data(withJSONObject: ["hooks": hooks], options: [.sortedKeys]).write(to: file)
        return file
    }

    @Test func writeOnSevenHookInstallAddsNothing() throws {
        let file = try writeLegacySevenHookFile()
        let before = try Data(contentsOf: file)
        let dir = file.deletingLastPathComponent()
        let siblingsBefore = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(file.lastPathComponent) }
        #expect(try HookInstaller.write(agent: .codex, shimPath: shim, into: file) == .alreadyPresent)
        #expect(try Data(contentsOf: file) == before)
        let siblingsAfter = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(file.lastPathComponent) }
        #expect(siblingsAfter == siblingsBefore)
    }

    @Test func removeClearsLegacySevenHooks() throws {
        let file = try writeLegacySevenHookFile()
        #expect(try HookInstaller.remove(agent: .codex, from: file).removed == true)
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        // Only Marshal's hooks were present, so nothing may remain under "hooks".
        #expect((root["hooks"] as? [String: Any] ?? [:]).isEmpty)
    }

    @Test func writeCreatesMissingFile() throws {
        let file = tempFile()
        #expect(try HookInstaller.write(agent: .codex, shimPath: shim, into: file) == .added)
        #expect(Set(try hooks(file).keys) == ["UserPromptSubmit", "PreToolUse", "PermissionRequest", "Stop", "SessionEnd"])
    }

    @Test func writeAddsHooksKeyWhenAbsent() throws {
        let file = tempFile()
        try Data(#"{"model":"opus","permissions":{"allow":["Bash"]}}"#.utf8).write(to: file)
        _ = try HookInstaller.write(agent: .claudeCode, shimPath: shim, into: file)
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        #expect(root["model"] as? String == "opus" && (root["permissions"] as? [String: Any]) != nil)
        #expect(try hooks(file).count == 8)
    }

    @Test func writeAppendsAfterExistingGroupsAndIsIdempotent() throws {
        let file = tempFile()
        try Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/orca/hook.sh"}]}]}}"#.utf8).write(to: file)
        #expect(try HookInstaller.write(agent: .claudeCode, shimPath: shim, into: file) == .added)
        let stop = try hooks(file)["Stop"] as! [[String: Any]]
        #expect(stop.count == 2)
        #expect(((stop[0]["hooks"] as! [[String: Any]])[0]["command"] as? String) == "/orca/hook.sh")
        #expect(try HookInstaller.write(agent: .claudeCode, shimPath: shim, into: file) == .alreadyPresent)
        #expect((try hooks(file)["Stop"] as! [[String: Any]]).count == 2)
        #expect(!String(decoding: try Data(contentsOf: file), as: UTF8.self).contains("\\/"))
    }

    @Test func writeMakesTimestampedBackup() throws {
        let file = tempFile()
        try Data("{}".utf8).write(to: file)
        let now = ISO8601DateFormatter().date(from: "2026-11-04T10:12:03Z")!
        _ = try HookInstaller.write(agent: .codex, shimPath: shim, into: file, now: now)
        let backups = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
            .filter { $0.hasPrefix(file.lastPathComponent + ".marshal-backup-") }
        #expect(backups.count == 1 && backups[0].hasSuffix("20261104-101203"))
    }

    @Test func removeDeletesOnlyOurGroups() throws {
        let file = tempFile()
        try Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/orca/hook.sh"}]}]},"model":"opus"}"#.utf8).write(to: file)
        _ = try HookInstaller.write(agent: .claudeCode, shimPath: shim, into: file)
        #expect(try HookInstaller.remove(agent: .claudeCode, from: file) == .init(removed: true, shiftedLaterGroups: false))
        let h = try hooks(file)
        #expect((h["Stop"] as! [[String: Any]]).count == 1 && h["Notification"] == nil)
        #expect(try HookInstaller.remove(agent: .claudeCode, from: file).removed == false)
    }

    @Test func removeReportsWhenLaterGroupsShift() throws {
        let file = tempFile()
        try Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/Users/ak/.marshal/bin/marshal hook codex"}]},{"hooks":[{"type":"command","command":"/orca/hook.sh"}]}]}}"#.utf8).write(to: file)
        let result = try HookInstaller.remove(agent: .codex, from: file)
        #expect(result.removed && result.shiftedLaterGroups)
        let stop = try hooks(file)["Stop"] as! [[String: Any]]
        #expect(stop.count == 1 && ((stop[0]["hooks"] as! [[String: Any]])[0]["command"] as? String) == "/orca/hook.sh")
    }

    @Test func writeThroughSymlinkKeepsLinkAndEditsTarget() throws {
        let target = tempFile()
        try Data("{}".utf8).write(to: target)
        let link = tempFile()
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(try HookInstaller.write(agent: .claudeCode, shimPath: shim, into: link) == .added)
        let type = try FileManager.default.attributesOfItem(atPath: link.path)[.type] as? FileAttributeType
        #expect(type == .typeSymbolicLink)
        #expect(try hooks(target).count == 8)
        #expect(try HookInstaller.remove(agent: .claudeCode, from: link).removed)
        #expect((try FileManager.default.attributesOfItem(atPath: link.path)[.type] as? FileAttributeType) == .typeSymbolicLink)
    }

    @Test func malformedJSONThrowsAndLeavesFileUntouched() throws {
        let file = tempFile()
        try Data("{oops".utf8).write(to: file)
        #expect(throws: (any Error).self) { try HookInstaller.write(agent: .codex, shimPath: shim, into: file) }
        #expect(String(decoding: try Data(contentsOf: file), as: UTF8.self) == "{oops")
        let siblings = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
            .filter { $0.hasPrefix(file.lastPathComponent + ".marshal-backup-") }
        #expect(siblings.isEmpty)
    }

    @Test func nonArrayEventValueThrowsAndLeavesFileUntouched() throws {
        for original in [#"{"hooks":{"Stop":{"x":1}}}"#, #"{"hooks":{"Stop":null}}"#] {
            let file = tempFile()
            try Data(original.utf8).write(to: file)
            #expect(throws: (any Error).self) { try HookInstaller.write(agent: .claudeCode, shimPath: shim, into: file) }
            #expect(String(decoding: try Data(contentsOf: file), as: UTF8.self) == original)
            let backups = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
                .filter { $0.hasPrefix(file.lastPathComponent + ".marshal-backup-") }
            #expect(backups.isEmpty)
        }
    }
}
