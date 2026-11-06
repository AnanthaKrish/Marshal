import AppKit
import MarshalCore
import Testing
@testable import Marshal

@MainActor
struct MenuInteractionTests {
    @Test func menuClicksKeepTheOwningPanelOpenAndOutsideClicksResumeAfterwards() async {
        let center = NotificationCenter()
        let interaction = MenuInteraction(center: center)
        let menu = NSMenu()
        #expect(interaction.shouldDismiss(isExpanded: true, clickedInside: false))
        #expect(!interaction.shouldDismiss(isExpanded: true, clickedInside: true))
        center.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        #expect(!interaction.shouldDismiss(isExpanded: true, clickedInside: false))
        center.post(name: NSMenu.didEndTrackingNotification, object: menu)
        // The selection's final mouse event must not dismiss the widget either.
        #expect(!interaction.shouldDismiss(isExpanded: true, clickedInside: false))
        await nextEventTurn()
        #expect(interaction.shouldDismiss(isExpanded: true, clickedInside: false))
    }

    @Test func nestedMenusStayProtectedUntilBothClose() async {
        let center = NotificationCenter()
        let interaction = MenuInteraction(center: center)
        let menu = NSMenu()
        let submenu = NSMenu()
        center.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        center.post(name: NSMenu.didBeginTrackingNotification, object: submenu)
        center.post(name: NSMenu.didEndTrackingNotification, object: menu)
        await nextEventTurn()
        #expect(interaction.isTracking)
        center.post(name: NSMenu.didEndTrackingNotification, object: submenu)
        await nextEventTurn()
        #expect(!interaction.isTracking)
    }

    @Test func reopeningBeforeThePreviousCloseFinishesKeepsProtection() async {
        let center = NotificationCenter()
        let interaction = MenuInteraction(center: center)
        let menu = NSMenu()
        center.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        center.post(name: NSMenu.didEndTrackingNotification, object: menu)
        center.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        await nextEventTurn()
        #expect(interaction.isTracking)
        center.post(name: NSMenu.didEndTrackingNotification, object: menu)
        await nextEventTurn()
        #expect(!interaction.isTracking)
    }

    @Test func colourActionsPersistAndReopeningReflectsTheSelection() throws {
        _ = NSApplication.shared
        let suite = "MarshalMenuTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = MarshalState(defaults: defaults)
        let focus = FocusCoordinator()
        state.isRobotExpanded = true
        let menu = PanelOptionsMenu.make(state: state, focus: focus)
        let colours = try #require(menu.items.first { $0.title == "Pookie's colour" }?.submenu)
        #expect(colours.items.map(\.title) == PookieSkin.all.map(\.name))
        let mint = try #require(colours.items.firstIndex { $0.title == "Mint" })
        colours.performActionForItem(at: mint)
        #expect(state.skinID == PookieSkin.mint.id)
        #expect(MarshalState(defaults: defaults).skinID == PookieSkin.mint.id)
        #expect(state.isRobotExpanded)
        let reopened = PanelOptionsMenu.make(state: state, focus: focus)
        let reopenedColours = try #require(reopened.items.first { $0.title == "Pookie's colour" }?.submenu)
        #expect(reopenedColours.items.filter { $0.state == .on }.map(\.title) == ["Mint"])
    }

    private func nextEventTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
