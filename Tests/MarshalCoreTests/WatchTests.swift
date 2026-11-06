import Foundation
import Testing
@testable import MarshalCore

struct WatchRuleTests {
    @Test func oldSettingsKeepConnectionsAndThresholdsWhenBackgroundOptionIsAdded() throws {
        var original = WatchSettings()
        original.enabled = true; original.browsers = ["com.google.Chrome"]
        original.rules[0].gentleMinutes = 1
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "countInBackground")
        let restored = try JSONDecoder().decode(WatchSettings.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored == original && !restored.countInBackground)
    }
    @Test func counterShowsProgressDuringTheFirstMinuteAndAcrossBoundaries() {
        #expect(WatchText.counter(0) == "0:00")
        #expect(WatchText.counter(5.9) == "0:05")
        #expect(WatchText.counter(59.9) == "0:59")
        #expect(WatchText.counter(60) == "1:00")
        #expect(WatchText.counter(3599) == "59:59")
        #expect(WatchText.counter(3605) == "1:00:05")
        #expect(WatchText.counter(.infinity) == "0:00")
        #expect(WatchText.counter(-5) == "0:00")
    }
    @Test func pastedURLsKeepOnlyTheDomainAndRejectNonWebAddresses() {
        #expect(WatchRule.domain(" HTTPS://YouTube.com/watch?v=private#fragment ") == "youtube.com")
        #expect(WatchRule.domain("m.youtube.com.") == "m.youtube.com")
        for invalid in ["file:///private/file", "javascript:alert(1)", "https://me:secret@example.com", "https://bad..com", "not a site"] {
            #expect(WatchRule.domain(invalid) == nil)
        }
    }
    @Test func domainMatchingUsesBoundariesAndMostSpecificEnabledRule() {
        var settings = WatchSettings()
        #expect(settings.match(host: "m.youtube.com", app: "browser")?.name == "YouTube")
        #expect(settings.match(host: "notyoutube.com", app: "browser") == nil)
        #expect(settings.match(host: "youtube.com.evil.test", app: "browser") == nil)
        settings.rules.append(WatchRule(kind: .site, target: "music.youtube.com", name: "Music", gentleMinutes: 60, firmMinutes: 90))
        #expect(settings.match(host: "music.youtube.com", app: "browser")?.gentleMinutes == 60)
        settings.rules[settings.rules.count - 1].enabled = false
        #expect(settings.match(host: "music.youtube.com", app: "browser")?.name == "YouTube")
        #expect(settings.match(host: nil, app: "com.apple.TV")?.name == "Apple TV")
    }
    @Test func settingsRejectInvalidThresholdsAndDuplicateRules() {
        var settings = WatchSettings()
        #expect(settings.isValid)
        settings.rules[0].firmMinutes = 30
        #expect(!settings.isValid)
        settings.rules[0].firmMinutes = 45
        settings.rules.append(settings.rules[0])
        #expect(!settings.isValid)
    }
}

struct WatchEngineTests {
    private let rule = WatchRule(kind: .site, target: "youtube.com", name: "YouTube")
    private func advance(_ engine: inout WatchEngine, from start: Double = 0, to end: Double) {
        for time in stride(from: start, through: end, by: 5) { engine.observe(ruleID: rule.id, at: time) }
    }
    @Test func firstSampleCountsNothingAndOnlyConsecutiveMatchingSamplesAddTime() {
        var engine = WatchEngine()
        engine.observe(ruleID: rule.id, at: 0)
        #expect(engine.displayed?.elapsed == 0)
        engine.observe(ruleID: rule.id, at: 5)
        engine.observe(ruleID: nil, at: 10)
        engine.observe(ruleID: rule.id, at: 15)
        #expect(engine.displayed?.elapsed == 5)
        engine.observe(ruleID: rule.id, at: 20)
        #expect(engine.displayed?.elapsed == 10)
    }
    @Test func thirtyAndFortyFiveMinuteBoundariesProduceDistinctStages() {
        var engine = WatchEngine()
        advance(&engine, to: 1795)
        #expect(engine.request(rule: rule, at: 1795) == nil)
        advance(&engine, from: 1800, to: 1800)
        let gentle = engine.request(rule: rule, at: 1800)
        #expect(gentle?.kind == .watchGentle)
        advance(&engine, from: 1805, to: 2700)
        #expect(engine.request(rule: rule, at: 2700)?.kind == .watchFirm)
        #expect(engine.request(rule: rule, at: 2700)?.id != gentle?.id)
    }
    @Test func sleepGapsAndBackwardClocksNeverAddUnobservedTime() {
        var engine = WatchEngine()
        advance(&engine, to: 10)
        engine.observe(ruleID: rule.id, at: 50)
        #expect(engine.displayed?.elapsed == 10)
        engine.observe(ruleID: rule.id, at: 500)
        #expect(engine.displayed?.elapsed == 0)
        engine.observe(ruleID: rule.id, at: 505)
        engine.observe(ruleID: rule.id, at: 1)
        #expect(engine.displayed?.elapsed == 0)
        engine.observe(ruleID: rule.id, at: .infinity)
        #expect(engine.displayed?.elapsed == 0)
    }
    @Test func switchingTargetsPausesEachCounterAndLongAbsenceCreatesNewEpisode() {
        var engine = WatchEngine()
        advance(&engine, to: 10)
        let original = engine.displayed?.id
        engine.observe(ruleID: "other", at: 15)
        engine.observe(ruleID: "other", at: 20)
        engine.observe(ruleID: rule.id, at: 25)
        #expect(engine.sessions["other"]?.elapsed == 5 && engine.displayed?.elapsed == 10)
        engine.observe(ruleID: nil, at: 30)
        engine.observe(ruleID: rule.id, at: 326)
        #expect(engine.displayed?.elapsed == 0 && engine.displayed?.id != original)
    }
    @Test func dismissGentleDoesNotHideLaterFirmAndPauseWithdrawsTheRequest() {
        var engine = WatchEngine()
        advance(&engine, to: 1800)
        engine.dismiss(rule: rule)
        #expect(engine.request(rule: rule, at: 1800) == nil)
        advance(&engine, from: 1805, to: 2700)
        #expect(engine.request(rule: rule, at: 2700)?.kind == .watchFirm)
        engine.observe(ruleID: nil, at: 2705)
        #expect(engine.request(rule: rule, at: 2705) == nil)
        engine.observe(ruleID: rule.id, at: 2710)
        engine.dismiss(rule: rule)
        #expect(engine.request(rule: rule, at: 2710) == nil)
    }
    @Test func snoozeKeepsCountingButSuppressesUntilTheDeadlineAndResetClearsIt() {
        var engine = WatchEngine()
        advance(&engine, to: 1800)
        engine.snooze(at: 1800)
        advance(&engine, from: 1805, to: 2395)
        #expect(engine.request(rule: rule, at: 2395) == nil)
        engine.observe(ruleID: rule.id, at: 2400)
        #expect(engine.request(rule: rule, at: 2400) != nil)
        engine.resetCurrent()
        #expect(engine.displayed == nil && engine.currentRuleID == nil)
    }
}

@MainActor
struct WatchStoreTests {
    @Test func onlySettingsPersistAndDisabledTrackingClearsCounters() throws {
        let suite = "WatchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = WatchTestClock()
        let watch = WatchStore(defaults: defaults, uptime: { clock.seconds })
        #expect(!watch.settings.enabled)
        watch.configure { $0.enabled = true; $0.rules[0].gentleMinutes = 1; $0.rules[0].firmMinutes = 2 }
        for t in stride(from: 0.0, through: 60, by: 5) {
            clock.seconds = t
            watch.observe(ruleID: watch.settings.rules[0].id, status: "Counting")
        }
        #expect(watch.request?.kind == .watchGentle)
        let restored = WatchStore(defaults: defaults)
        #expect(restored.settings.enabled && restored.session == nil && restored.request == nil)
        let saved = String(decoding: try #require(defaults.data(forKey: WatchStore.storageKey)), as: UTF8.self)
        #expect(!saved.contains("elapsed") && !saved.contains("lastSeen"))
        watch.configure { $0.enabled = false }
        #expect(watch.session == nil && watch.request == nil && !watch.isCounting)
    }
    @Test func previewsRepeatAndClearWithoutChangingSettingsOrRealCounters() {
        let watch = WatchStore()
        let settings = watch.settings
        watch.preview(firm: true)
        let first = watch.request?.id
        #expect(watch.request?.kind == .watchFirm && watch.session == nil)
        watch.preview(firm: true)
        #expect(watch.request?.id != first)
        watch.snooze()
        #expect(watch.request == nil && watch.previewLevel == nil && watch.settings == settings)
    }
    @Test func invalidSettingsAreRejectedAndRemovingARuleWithdrawsItsNudge() {
        let clock = WatchTestClock()
        let watch = WatchStore(uptime: { clock.seconds })
        watch.configure { $0.enabled = true; $0.rules[0].gentleMinutes = 1; $0.rules[0].firmMinutes = 2 }
        #expect(!watch.configure { $0.rules[0].gentleMinutes = -1 })
        let id = watch.settings.rules[0].id
        for t in stride(from: 0.0, through: 60, by: 5) {
            clock.seconds = t; watch.observe(ruleID: id, status: "Counting")
        }
        #expect(watch.request != nil)
        watch.configure { $0.rules.removeAll { $0.id == id } }
        #expect(watch.request == nil && watch.session == nil)
    }
}

@MainActor
struct WatchArbitrationTests {
    @Test func focusMakesWatchFirmerQuietSuppressesAndPermissionStillWins() {
        let focus = FocusCoordinator()
        let request = AttentionRequest(id: "watch:one", kind: .watchGentle, title: "Break?", detail: "YouTube")
        focus.updateWatch(request)
        #expect(focus.nudge?.kind == .watchGentle && focus.isWatchYawning)
        focus.startFocus(minutes: 25)
        #expect(focus.nudge?.kind == .watchFirm)
        let store = AgentSessionStore()
        store.apply(AgentEvent(agent: "codex", session: "one", state: .needsPermission))
        focus.update(sessions: store.sessions, conditions: [])
        #expect(focus.nudge?.kind == .permission)
        focus.quiet(forMinutes: 15)
        #expect(focus.nudge == nil)
    }
    @Test func returningToAWatchStageDoesNotRepeatItsGesture() {
        let focus = FocusCoordinator()
        let request = AttentionRequest(id: "watch:one", kind: .watchGentle, title: "Break?", detail: "YouTube")
        focus.updateWatch(request)
        let pulse = focus.nudgePulse
        focus.updateWatch(nil)
        focus.updateWatch(request)
        #expect(focus.nudgePulse == pulse && !focus.isWatchYawning)
        focus.updateWatch(AttentionRequest(id: "watch:two", kind: .watchFirm, title: "Break?", detail: "YouTube"))
        #expect(focus.nudgePulse == pulse + 1 && focus.activity == .waiting)
    }
}

@MainActor
private final class WatchTestClock { var seconds = 0.0 }
