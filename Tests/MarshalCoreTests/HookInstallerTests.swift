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
        #expect(Set(claude.keys) == ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "PostToolUseFailure", "Notification", "Stop", "StopFailure", "SessionEnd"])
        let codex = HookInstaller.fragment(for: .codex, shimPath: shim)["hooks"] as! [String: Any]
        #expect(Set(codex.keys) == ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "Interrupt", "Stop", "SessionEnd"])
        let notif = (claude["Notification"] as! [[String: Any]])[0]
        #expect(notif["matcher"] as? String == "permission_prompt|agent_needs_input")
        let entry = ((claude["Stop"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]])[0]
        #expect(entry["command"] as? String == "'\(shim)' hook claude-code Stop" && entry["async"] as? Bool == false && entry["timeout"] as? Int == 1)
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

    @Test func oldInstallationUpgradesInPlaceAndThenIsIdempotent() throws {
        let file = try writeLegacySevenHookFile()
        #expect(try HookInstaller.write(agent: .codex, shimPath: shim, into: file) == .updated)
        let upgraded = try Data(contentsOf: file)
        #expect(try hooks(file)["PostToolUse"] != nil)
        #expect(try HookInstaller.write(agent: .codex, shimPath: shim, into: file) == .alreadyPresent)
        #expect(try Data(contentsOf: file) == upgraded)
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
        #expect(Set(try hooks(file).keys) == ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "Interrupt", "Stop", "SessionEnd"])
    }

    @Test func writeAddsHooksKeyWhenAbsent() throws {
        let file = tempFile()
        try Data(#"{"model":"opus","permissions":{"allow":["Bash"]}}"#.utf8).write(to: file)
        _ = try HookInstaller.write(agent: .claudeCode, shimPath: shim, into: file)
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        #expect(root["model"] as? String == "opus" && (root["permissions"] as? [String: Any]) != nil)
        #expect(try hooks(file).count == 10)
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
        #expect(try hooks(target).count == 10)
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

struct ProviderInstallerTests {
    private func file() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("marshal-provider-\(UUID()).json") }
    private let shim = "/Users/O'Neil Work/.marshal/bin/marshal"

    @Test func cursorFlatSchemaPreservesOtherHooksAndSettings() throws {
        let file = file()
        let original = #"{"version":1,"custom":"keep","hooks":{"stop":[{"command":"/other/hook","timeout":7}],"beforeTabFileRead":[{"command":"/policy"}],"unrelatedEmpty":[]}}"#
        try Data(original.utf8).write(to: file)
        #expect(try HookInstaller.write(agent: .cursor, shimPath: shim, into: file) == .added)
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        let hooks = root["hooks"] as! [String: Any]
        let stops = hooks["stop"] as! [[String: Any]]
        #expect(root["version"] as? Int == 1 && root["custom"] as? String == "keep")
        #expect(stops.count == 2 && stops[0]["command"] as? String == "/other/hook")
        #expect(stops[1]["hooks"] == nil && stops[1]["async"] == nil)
        #expect(try HookInstaller.write(agent: .cursor, shimPath: shim, into: file) == .alreadyPresent)
        #expect(try HookInstaller.remove(agent: .cursor, from: file).removed)
        let restored = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! NSDictionary
        #expect(try restored.isEqual(to: JSONSerialization.jsonObject(with: Data(original.utf8)) as! [AnyHashable: Any]))
        #expect(try HookInstaller.remove(agent: .cursor, from: file).removed == false)
    }

    @Test func removalKeepsOtherHandlersInTheSameGroupAndOtherProviders() throws {
        let file = file()
        let original = #"{"hooks":{"Stop":[{"matcher":"keep","hooks":[{"command":"/Users/a/.marshal/bin/marshal hook claude-code"},{"command":"/Users/a/.marshal/bin/marshal hook codex"},{"command":"echo /Users/a/.marshal/bin/marshal hook claude-code"}]}]}}"#
        try Data(original.utf8).write(to: file)
        #expect(try HookInstaller.remove(agent: .claudeCode, from: file).removed)
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        let group = ((root["hooks"] as! [String: Any])["Stop"] as! [[String: Any]])[0]
        let entries = group["hooks"] as! [[String: Any]]
        #expect(entries.count == 2 && group["matcher"] as? String == "keep")
        #expect(entries[0]["command"] as? String == "/Users/a/.marshal/bin/marshal hook codex")
    }

    @Test func unknownCursorVersionIsNotOverwritten() throws {
        let file = file()
        let data = Data(#"{"version":99,"hooks":{}}"#.utf8)
        try data.write(to: file)
        #expect(throws: (any Error).self) { try HookInstaller.write(agent: .cursor, shimPath: shim, into: file) }
        #expect(try Data(contentsOf: file) == data)
    }

    @Test func upgradePreservesCodexGroupIndexesAndCustomFields() throws {
        let file = file()
        try Data(#"{"hooks":{"Stop":[{"hooks":[{"command":"/before"}]},{"hooks":[{"command":"/Users/a/.marshal/bin/marshal hook codex","async":true,"custom":"keep"}]},{"hooks":[{"command":"/after"}]}]}}"#.utf8).write(to: file)
        #expect(try HookInstaller.write(agent: .codex, shimPath: shim, into: file) == .updated)
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        let groups = (root["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
        #expect(groups.count == 3)
        #expect((groups[0]["hooks"] as! [[String: Any]])[0]["command"] as? String == "/before")
        #expect((groups[2]["hooks"] as! [[String: Any]])[0]["command"] as? String == "/after")
        let ours = (groups[1]["hooks"] as! [[String: Any]])[0]
        #expect(ours["async"] as? Bool == false && ours["custom"] as? String == "keep")
    }
}

extension ProviderInstallerTests {
    @Test func quotedCommandExecutesWithSpacesAndApostrophesInPath() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Marshal O'Neil \(UUID())")
        let executable = folder.appendingPathComponent(".marshal/bin/marshal")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("#!/bin/sh\nprintf '%s\\n' \"$@\"\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let fragment = HookInstaller.fragment(for: .cursor, shimPath: executable.path)
        let hooks = fragment["hooks"] as! [String: Any]
        let command = (hooks["stop"] as! [[String: Any]])[0]["command"] as! String
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]; process.standardOutput = pipe
        try process.run(); process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(process.terminationStatus == 0 && output == "hook\ncursor\nstop\n")
    }

    @Test func configurationStatusDistinguishesMissingOldAndUpdatedHooks() throws {
        let file = file()
        #expect(HookInstaller.installation(for: .codex, at: file) == .missing)
        try Data(#"{"hooks":{"Stop":[{"hooks":[{"command":"/Users/a/.marshal/bin/marshal hook codex","async":true}]}]}}"#.utf8).write(to: file)
        #expect(HookInstaller.installation(for: .codex, at: file) == .needsUpdate)
        _ = try HookInstaller.write(agent: .codex, shimPath: shim, into: file)
        #expect(HookInstaller.installation(for: .codex, at: file) == .ready)
        try Data("broken json".utf8).write(to: file)
        #expect(HookInstaller.installation(for: .codex, at: file) == .unreadable)
    }
}
