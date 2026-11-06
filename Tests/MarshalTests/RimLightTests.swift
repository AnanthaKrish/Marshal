import AppKit
import MarshalCore
import Testing
@testable import Marshal

@MainActor
struct RimLightTests {
    @Test func selectedLightPersistsAndUnknownPreferenceFallsBack() throws {
        let suite = "MarshalRimLightTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("removed-style", forKey: "marshal.pookie.completionLight")
        let state = MarshalState(defaults: defaults)
        #expect(state.completionLightStyle == .trace)
        state.completionLightStyle = .off
        #expect(MarshalState(defaults: defaults).completionLightStyle == .off)
    }

    @Test func previewsReplayAndStopWithoutChangingTheSavedChoice() throws {
        let suite = "MarshalPreviewTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = MarshalState(defaults: defaults)
        let preview = RimLightPreviewModel(selected: state.completionLightStyle)
        preview.play(.breathe)
        let first = preview.trigger
        preview.play()
        #expect(preview.trigger == first + 1 && preview.isPlaying)
        #expect(preview.selected == .breathe && state.completionLightStyle == .trace)
        preview.tryAll()
        #expect(preview.isTryingAll)
        preview.stop()
        #expect(!preview.isPlaying && !preview.isTryingAll)
        #expect(MarshalState(defaults: defaults).completionLightStyle == .trace)
    }

    @Test func lightsStaySmoothTraceSettlesAndReducedMotionIsSteady() {
        for style in CompletionLightStyle.allCases {
            var previous = style.sample(at: 0)
            for time in stride(from: 0.0, through: 8.0, by: 0.05) {
                let sample = style.sample(at: time)
                #expect((0...1).contains(sample.opacity) && (0...1).contains(sample.traceOpacity))
                #expect(abs(sample.opacity - previous.opacity) < 0.02)
                if style == .off { #expect(sample.opacity == 0 && sample.trace == nil) }
                if style == .breathe { #expect(sample.opacity >= 0.45 && sample.opacity <= 0.75) }
                if style == .trace && time >= CompletionLightStyle.cycleDuration { #expect(sample == .steady) }
                let still = style.sample(at: time, reduceMotion: true)
                #expect(still == (style == .off ? CompletionLightSample(opacity: 0) : .steady))
                previous = sample
            }
        }
        #expect(CompletionLightStyle.trace.sample(at: 2).trace == 0.5)
        #expect(CompletionLightStyle.breathe.sample(at: 0) == CompletionLightStyle.breathe.sample(at: 4))
    }

    @Test func lightPreviewIsReachableFromEitherPanelOptions() throws {
        _ = NSApplication.shared
        let suite = "MarshalRimLightMenuTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let menu = PanelOptionsMenu.make(state: MarshalState(defaults: defaults), focus: FocusCoordinator())
        #expect(menu.items.contains { $0.title == "Rim light…" && $0.isEnabled && $0.action != nil })
    }
}
