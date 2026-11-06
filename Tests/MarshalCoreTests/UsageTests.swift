import Foundation
import Testing
@testable import MarshalCore

struct UsageParsingTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    @Test func claudeReportsContextAndBothWindowsWithoutKeepingOtherFields() throws {
        let data = Data(#"{"session_id":"one","context_window":{"used_percentage":72.5,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":81,"resets_at":2001000},"seven_day":{"used_percentage":23,"resets_at":2010000}},"transcript_path":"/private/transcript","prompt":"PRIVATE_SENTINEL"}"#.utf8)
        let sample = try #require(UsageParsing.claude(data, now: now))
        #expect(sample.context?.usedPercent == 72.5)
        #expect(sample.context?.capacity == 200000 && sample.context?.usedTokens == nil)
        #expect(sample.windows?.map(\.usedPercent) == [81, 23])
        let saved = String(decoding: try JSONEncoder().encode(sample), as: UTF8.self)
        #expect(!saved.contains("PRIVATE_SENTINEL") && !saved.contains("transcript"))
    }

    @Test func missingClaudeDataIsUnknownAndCompactionCanClearContext() throws {
        let sample = try #require(UsageParsing.claude(Data(#"{"session_id":"one","context_window":{"used_percentage":null}}"#.utf8), now: now))
        #expect(sample.context == nil && sample.windows == nil)
        #expect(UsageParsing.claude(Data(#"{"context_window":{"used_percentage":10}}"#.utf8)) == nil)
    }

    @Test func invalidPercentagesAreDroppedAndInvalidCapacityIsNotUsed() throws {
        let invalid = try #require(UsageParsing.claude(Data(#"{"session_id":"one","context_window":{"used_percentage":-3},"rate_limits":{"five_hour":{"used_percentage":200}}}"#.utf8)))
        #expect(invalid.context == nil && invalid.windows == [])
        let capacity = try #require(UsageParsing.claude(Data(#"{"session_id":"one","context_window":{"used_percentage":50,"context_window_size":-20}}"#.utf8)))
        #expect(capacity.context?.usedPercent == 50 && capacity.context?.capacity == nil)
    }

    @Test func codexContextUsesLastRequestRatherThanLifetimeTotal() throws {
        let sample = try #require(UsageParsing.codexRecord(Data(Self.record.utf8), session: "chat"))
        #expect(sample.context?.usedPercent == 25)
        #expect(sample.context?.usedTokens == 50000)
        #expect(sample.context?.isEstimate == true)
        #expect(sample.windows == nil)
    }

    @Test func unrelatedCodexRecordsAndMissingUsageAreIgnored() {
        #expect(UsageParsing.codexRecord(Data(#"{"type":"response_item","payload":{"type":"message","content":"PRIVATE"}}"#.utf8), session: "chat") == nil)
        #expect(UsageParsing.codexRecord(Data(#"{"type":"event_msg","timestamp":"2026-11-04T12:00:00Z","payload":{"type":"token_count","info":null}}"#.utf8), session: "chat") == nil)
    }

    @Test func codexWindowNamesComeFromReportedDurations() throws {
        let data = Data(#"{"rateLimits":{"primary":{"usedPercent":4,"windowDurationMins":10080,"resetsAt":2010000},"secondary":null}}"#.utf8)
        let sample = try #require(UsageParsing.codexLimits(data, now: now))
        #expect(sample.windows?.count == 1)
        #expect(sample.windows?.first?.title == "Weekly")
        #expect(sample.windows?.first?.usedPercent == 4)
        #expect(UsageParsing.codexLimits(Data(#"{"unexpected":true}"#.utf8)) == nil)
    }

    @Test func multipleCodexBucketsAreNotSummedOrDuplicated() throws {
        let data = Data(#"{"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":20,"windowDurationMins":300}},"review":{"limitId":"review","limitName":"Review","primary":{"usedPercent":75,"windowDurationMins":10080}}}}"#.utf8)
        let sample = try #require(UsageParsing.codexLimits(data))
        #expect(sample.windows?.map(\.usedPercent) == [20, 75])
        #expect(sample.windows?.last?.title == "Review · Weekly")
    }

    @Test func colorsUseUsedPercentAndResetDoesNotInventZeroUsage() {
        #expect(UsageLevel.forUsedPercent(69.9) == .healthy)
        #expect(UsageLevel.forUsedPercent(70) == .caution)
        #expect(UsageLevel.forUsedPercent(90) == .critical)
        #expect(UsageLevel.forUsedPercent(nil) == .unknown)
        #expect(UsageLevel.forUsedPercent(.nan) == .unknown)
        let window = UsageWindow(id: "5h", title: "5h", usedPercent: 100, resetsAt: now)
        #expect(window.hasReset(at: now))
        #expect(window.usedPercent == 100)
    }

    static let record = #"{"timestamp":"2026-11-04T12:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":50000},"total_token_usage":{"total_tokens":9000000},"model_context_window":200000}}}"#
}

@MainActor
struct UsageStoreTests {
    @Test func contextUpdatesDoNotEraseLimitsAndOlderSamplesCannotUndoCompaction() {
        let now = Date.now
        let store = UsageStore()
        store.apply(UsageSample(agent: "claude-code", session: "chat",
                                context: ContextUsage(usedPercent: 80, updatedAt: now),
                                windows: [UsageWindow(id: "5h", title: "5h", usedPercent: 30)], updatedAt: now), now: now)
        store.apply(UsageSample(agent: "claude-code", session: "chat", updatedAt: now.addingTimeInterval(1)), now: now)
        #expect(store.contexts["claude-code:chat"] == nil)
        #expect(store.providers["claude-code"]?.windows.first?.usedPercent == 30)
        store.apply(UsageSample(agent: "claude-code", session: "chat",
                                context: ContextUsage(usedPercent: 99, updatedAt: now), updatedAt: now), now: now)
        #expect(store.contexts["claude-code:chat"] == nil)
    }

    @Test func badDatesAndProvidersAreRejectedAndRefreshFailuresKeepLastReading() {
        let now = Date.now
        let store = UsageStore()
        store.apply(UsageSample(agent: "codex", windows: [UsageWindow(id: "week", title: "Weekly", usedPercent: 40)], updatedAt: now), now: now)
        store.setMessage("Unavailable", for: "codex")
        #expect(store.providers["codex"]?.windows.first?.usedPercent == 40)
        store.apply(UsageSample(agent: "codex", windows: [], updatedAt: now.addingTimeInterval(1000)), now: now)
        store.apply(UsageSample(agent: "other", windows: [], updatedAt: now), now: now)
        #expect(store.providers["other"] == nil && store.providers["codex"]?.windows.count == 1)
        #expect(store.providers["codex"]?.isStale(at: now.addingTimeInterval(301)) == true)
    }
}

struct UsageFilesTests {
    @Test func cacheNamesCannotEscapeAndFilesArePrivate() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try UsageCache.write(UsageSample(agent: "claude-code", session: "../../outside", updatedAt: .now), directory: dir)
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        #expect(files.count == 1 && files[0].lastPathComponent.count == 69)
        let attrs = try FileManager.default.attributesOfItem(atPath: files[0].path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func tailReaderSkipsMessagesAndIncompleteNewestRecord() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let content = UsageParsingTests.record + "\n" + #"{"type":"response_item","payload":{"content":"PRIVATE"}}"# + "\n" + #"{"type":"event_msg","payload":{"type":"token_count"#
        try Data(content.utf8).write(to: file)
        let sample = try #require(UsageFiles.latestCodexSample(file: file, session: "chat"))
        #expect(sample.context?.usedPercent == 25)
    }

    @Test func onlyKnownChatFilesAreReadAndUnchangedFilesAreSkipped() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let id = UUID().uuidString
        try Data((UsageParsingTests.record + "\n").utf8).write(to: dir.appendingPathComponent("rollout-\(id).jsonl"))
        let reader = UsageFiles(cacheDirectory: dir.appendingPathComponent("cache"), codexDirectory: dir)
        #expect(await reader.read(sessions: []).isEmpty)
        #expect(await reader.read(sessions: [id]).count == 1)
        #expect(await reader.read(sessions: [id]).isEmpty)
    }
}

struct UsageInstallerTests {
    @Test func freshInstallConnectsOnlyMarshalAndRemovalClearsItsStatusLine() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let settings = dir.appendingPathComponent(".claude/settings.json")
        let saved = dir.appendingPathComponent(".marshal/saved.json")
        let shim = dir.appendingPathComponent(".marshal/bin/marshal").path
        #expect(try UsageInstaller.install(settings: settings, saved: saved, shim: shim))
        let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
        #expect(root.keys.sorted() == ["statusLine"])
        let status = try #require(root["statusLine"] as? [String: String])
        #expect(status == ["type": "command", "command": UsageInstaller.shellQuote(shim) + " usage claude"])
        #expect(UsageInstaller.originalCommand(saved: saved) == nil)
        #expect(try !UsageInstaller.install(settings: settings, saved: saved, shim: shim))
        #expect(try UsageInstaller.remove(settings: settings, saved: saved))
        let restored = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
        #expect(restored.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: saved.path))
    }

    @Test func settingsWithoutAStatusLineSurviveConnectAndDisconnect() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let settings = dir.appendingPathComponent("settings.json"), saved = dir.appendingPathComponent("saved.json")
        let original: [String: Any] = ["hooks": ["Stop": []], "permissions": ["allow": ["Read"]]]
        try JSONSerialization.data(withJSONObject: original).write(to: settings)
        #expect(try UsageInstaller.install(settings: settings, saved: saved, shim: "/tmp/marshal"))
        #expect(UsageInstaller.originalCommand(saved: saved) == nil)
        #expect(try UsageInstaller.remove(settings: settings, saved: saved))
        let restored = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? NSDictionary)
        #expect(restored == original as NSDictionary)
    }

    @Test func existingStatusLineReceivesExactInputEvenBeyondAPipeBuffer() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let output = try FileHandle(forWritingTo: file)
        let data = Data(String(repeating: "original payload\n", count: 10000).utf8)
        StatusLineForwarder.run(command: "/bin/cat", input: data, output: output, timeout: 2)
        try output.close()
        #expect(try Data(contentsOf: file) == data)
    }

    @Test func existingStatusLineAndSettingsSurviveInstallRemoveAndRepeatInstall() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let settings = dir.appendingPathComponent("settings.json"), saved = dir.appendingPathComponent("saved.json")
        let command = #"printf 'custom status $HOME'; cat"#
        let root: [String: Any] = ["statusLine": ["type": "command", "command": command, "padding": 2],
                                   "hooks": ["Stop": []], "permissions": ["allow": ["Read"]]]
        try JSONSerialization.data(withJSONObject: root).write(to: settings)
        #expect(try UsageInstaller.install(settings: settings, saved: saved, shim: "/tmp/a b/'marshal"))
        #expect(try !UsageInstaller.install(settings: settings, saved: saved, shim: "/tmp/a b/'marshal"))
        #expect(UsageInstaller.originalCommand(saved: saved) == command)
        let installed = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
        #expect((installed["statusLine"] as? [String: Any])?["padding"] as? Int == 2)
        #expect(try UsageInstaller.remove(settings: settings, saved: saved))
        let restored = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? NSDictionary)
        #expect(restored == root as NSDictionary)
    }

    @Test func removalDoesNotOverwriteAStatusLineChangedAfterInstall() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let settings = dir.appendingPathComponent("settings.json"), saved = dir.appendingPathComponent("saved.json")
        _ = try UsageInstaller.install(settings: settings, saved: saved, shim: "/tmp/marshal")
        let replacement = Data(#"{"statusLine":{"type":"command","command":"new-tool"}}"#.utf8)
        try replacement.write(to: settings)
        #expect(throws: UsageInstaller.InstallError.self) { try UsageInstaller.remove(settings: settings, saved: saved) }
        #expect(try Data(contentsOf: settings) == replacement)
    }
}

struct ClaudeUsageReporterTests {
    private let payload = Data(#"{"session_id":"standalone","context_window":{"used_percentage":42,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":73,"resets_at":2001000}}}"#.utf8)

    @Test func freshInstallCollectsUsageAndDisplaysContextWithoutAnotherStatusLine() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let saved = dir.appendingPathComponent(".marshal/saved.json")
        let cache = dir.appendingPathComponent(".marshal/usage")
        _ = try UsageInstaller.install(settings: dir.appendingPathComponent(".claude/settings.json"),
                                        saved: saved, shim: dir.appendingPathComponent(".marshal/bin/marshal").path)
        let textFile = dir.appendingPathComponent("output")
        FileManager.default.createFile(atPath: textFile.path, contents: nil)
        let output = try FileHandle(forWritingTo: textFile)
        ClaudeUsageReporter.report(payload, cacheDirectory: cache, savedStatusLine: saved, output: output)
        try output.close()
        #expect(try String(contentsOf: textFile, encoding: .utf8) == "Context 42%\n")
        let reader = UsageFiles(cacheDirectory: cache, codexDirectory: dir.appendingPathComponent("missing-codex"))
        let samples = await reader.read(sessions: [])
        #expect(samples.count == 1 && samples[0].session == "standalone")
        #expect(samples.first?.context?.usedPercent == 42)
        #expect(samples.first?.windows?.first?.usedPercent == 73)
    }

    @Test func failingOptionalStatusLineCannotPreventUsageCollection() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let saved = dir.appendingPathComponent("saved.json")
        let cache = dir.appendingPathComponent("usage")
        let original: [String: Any] = ["original": ["type": "command", "command": "exit 1"]]
        try JSONSerialization.data(withJSONObject: original).write(to: saved)
        ClaudeUsageReporter.report(payload, cacheDirectory: cache, savedStatusLine: saved, output: .nullDevice)
        let samples = await UsageFiles(cacheDirectory: cache, codexDirectory: dir.appendingPathComponent("missing-codex"))
            .read(sessions: [])
        #expect(samples.first?.context?.usedPercent == 42)
        #expect(samples.first?.windows?.first?.usedPercent == 73)
    }
}

struct CodexUsageClientTests {
    @Test func clientOnlyInitializesAndReadsLimits() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let executable = dir.appendingPathComponent("codex")
        let script = """
        #!/usr/bin/env python3
        import json,sys
        a=json.loads(sys.stdin.readline())
        assert a['method']=='initialize'
        print(json.dumps({'id':1,'result':{}}),flush=True)
        assert json.loads(sys.stdin.readline())['method']=='initialized'
        assert json.loads(sys.stdin.readline())['method']=='account/rateLimits/read'
        print(json.dumps({'id':2,'result':{'rateLimits':{'primary':{'usedPercent':42,'windowDurationMins':300,'resetsAt':2001000}}}}),flush=True)
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let result = try CodexUsageClient.read(executable: executable, timeout: 3)
        #expect(result.windows?.first?.usedPercent == 42)
    }

    @Test func unavailableAndStalledProcessesReturnWithoutHanging() throws {
        #expect(throws: CodexUsageError.self) { try CodexUsageClient.read(executable: nil) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("#!/bin/sh\nexec /bin/sleep 5\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        let start = Date.now
        #expect(throws: CodexUsageError.self) { try CodexUsageClient.read(executable: file, timeout: 0.15) }
        #expect(Date.now.timeIntervalSince(start) < 2)
    }
}
