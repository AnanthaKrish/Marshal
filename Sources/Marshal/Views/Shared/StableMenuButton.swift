import AppKit
import MarshalCore
import SwiftUI

/// Build once per click. SwiftUI timer/vitals refreshes may update the button,
/// but cannot replace the NSMenu while the user is navigating its submenus.
struct StableMenuButton: NSViewRepresentable {
    var style: SurfaceStyle
    var makeMenu: @MainActor () -> NSMenu

    func makeCoordinator() -> Coordinator { Coordinator(makeMenu: makeMenu) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Marshal options")!,
                              target: context.coordinator, action: #selector(Coordinator.openMenu(_:)))
        button.isBordered = false
        button.focusRingType = .none
        button.setAccessibilityLabel("Marshal options")
        button.toolTip = "Marshal options"
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.makeMenu = makeMenu
        button.contentTintColor = style == .notch ? .white.withAlphaComponent(0.6) : .secondaryLabelColor
    }

    @MainActor
    final class Coordinator: NSObject {
        var makeMenu: @MainActor () -> NSMenu
        init(makeMenu: @escaping @MainActor () -> NSMenu) { self.makeMenu = makeMenu }

        @objc func openMenu(_ sender: NSButton) {
            let menu = makeMenu()
            let below = sender.isFlipped ? sender.bounds.maxY + 4 : sender.bounds.minY - 4
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: below), in: sender)
        }
    }
}

@MainActor
enum PanelOptionsMenu {
    static func make(state: MarshalState, focus: FocusCoordinator) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item("Hourly stretch reminders", checked: focus.breaksEnabled) {
            focus.setBreaksEnabled(!focus.breaksEnabled)
        })
        menu.addItem(.separator())
        menu.addItem(item("Show Pookie", checked: state.isRobotVisible) { state.isRobotVisible.toggle() })
        menu.addItem(item("Show notch", checked: state.isNotchVisible) { state.isNotchVisible.toggle() })
        let colours = NSMenuItem(title: "Pookie's colour", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: colours.title)
        submenu.autoenablesItems = false
        for skin in PookieSkin.all {
            submenu.addItem(item(skin.name, checked: skin.id == state.skinID) { state.skinID = skin.id })
        }
        colours.submenu = submenu
        menu.addItem(colours)
        menu.addItem(item("Rim light…") { RimLightPreviewController.shared.show(state: state) })
        if FeatureAvailability.watchTime {
            menu.addItem(item("Watch-time reminders…") { state.showWatchSettings?() })
        }
        menu.addItem(.separator())
        menu.addItem(item("Set up Claude Code") { SetupPresenter.install(.claudeCode) })
        menu.addItem(item("Set up Codex") { SetupPresenter.install(.codex) })
        menu.addItem(item("Connect Claude usage") { SetupPresenter.connectUsage() })
        menu.addItem(.separator())
        menu.addItem(item("Quit Marshal") { state.quit() })
        return menu
    }

    private static func item(_ title: String, checked: Bool = false, action: @escaping @MainActor () -> Void) -> NSMenuItem {
        let handler = MenuAction(action)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.invoke), keyEquivalent: "")
        item.target = handler
        item.representedObject = handler // NSMenuItem.target is weak.
        item.state = checked ? .on : .off
        return item
    }
}

@MainActor
private final class MenuAction: NSObject {
    private let action: @MainActor () -> Void
    init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    @objc func invoke() { action() }
}
