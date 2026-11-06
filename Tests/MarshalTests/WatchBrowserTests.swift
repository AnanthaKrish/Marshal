import AppKit
import Carbon
import MarshalCore
import Testing
@testable import Marshal

@MainActor
struct WatchBrowserTests {
    @Test func browserGetRequestUsesTheCoreSuiteInsteadOfTheApplicationLifecycleClass() {
        let event = WatchBrowserReader.urlRequest(browser: WatchBrowser.all[1], target: .init(processIdentifier: 123))
        #expect(event.eventClass == 0x636f7265) // core, not aevt
        #expect(event.eventID == 0x67657464) // getd
        #expect(event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.descriptorType == DescType(typeObjectSpecifier))
    }
    @Test func browserRequestsOnlyTheSelectedTabURLOfTheFirstWindow() throws {
        for safari in [true, false] {
            let url = WatchBrowserReader.urlSpecifier(safari: safari)
            #expect(url.descriptorType == DescType(typeObjectSpecifier))
            #expect(url.forKeyword(AEKeyword(keyAEKeyData))?.typeCodeValue == (safari ? 0x7055524c : 0x55524c20))
            let tab = try #require(url.forKeyword(AEKeyword(keyAEContainer)))
            #expect(tab.forKeyword(AEKeyword(keyAEKeyData))?.typeCodeValue == (safari ? 0x63546162 : 0x61635461))
            let window = try #require(tab.forKeyword(AEKeyword(keyAEContainer)))
            #expect(window.forKeyword(AEKeyword(keyAEKeyData))?.int32Value == 1)
        }
    }
    @Test func parkedWatchFeatureHasNoSettingsEntry() throws {
        _ = NSApplication.shared
        let suite = "WatchMenuTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = MarshalState(defaults: defaults)
        let menu = PanelOptionsMenu.make(state: state, focus: FocusCoordinator())
        #expect(!FeatureAvailability.watchTime)
        #expect(!menu.items.contains { $0.title == "Watch-time reminders…" })
    }
}

