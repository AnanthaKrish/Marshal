import AppKit
import MarshalCore

/// Small menu-bar item. It exists so the user can always get the widgets back
/// (and quit) even if both are hidden.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let state: MarshalState
    private let robot: RobotWindowController
    private let item: NSStatusItem
    private let focus: FocusCoordinator
    private let focusItem = NSMenuItem(title: "Start 25-minute focus", action: #selector(toggleFocus), keyEquivalent: "")
    private let endFocusItem = NSMenuItem(title: "End focus", action: #selector(endFocus), keyEquivalent: "")
    private let quietItem = NSMenuItem(title: "Quiet for 30 minutes", action: #selector(toggleQuiet), keyEquivalent: "")

    private let robotItem = NSMenuItem(title: "Show Robot", action: #selector(toggleRobot), keyEquivalent: "")
    private let notchItem = NSMenuItem(title: "Show Notch Widget", action: #selector(toggleNotch), keyEquivalent: "")

    init(state: MarshalState, robot: RobotWindowController, focus: FocusCoordinator) {
        self.state = state
        self.robot = robot
        self.focus = focus
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: "Marshal")
            button.toolTip = "Marshal"
        }

        let menu = NSMenu()
        menu.delegate = self
        let about = NSMenuItem(title: "About Marshal", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        about.target = NSApp
        menu.addItem(about)
        menu.addItem(.separator())
        robotItem.target = self
        notchItem.target = self
        for control in [focusItem, endFocusItem, quietItem] {
            control.target = self
            menu.addItem(control)
        }
        menu.addItem(.separator())
        menu.addItem(robotItem)
        menu.addItem(notchItem)
        let rimLight = NSMenuItem(title: "Pookie rim light…", action: #selector(showRimLight), keyEquivalent: "")
        rimLight.target = self
        menu.addItem(rimLight)
        if FeatureAvailability.watchTime {
            let watch = NSMenuItem(title: "Watch-time reminders…", action: #selector(showWatchSettings), keyEquivalent: "")
            watch.target = self
            menu.addItem(watch)
        }
        menu.addItem(.separator())

        let reset = NSMenuItem(title: "Reset Robot Position", action: #selector(resetRobot), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Marshal", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        switch focus.timer.phase {
        case .idle, .completed: focusItem.title = "Start 25-minute focus"
        case .running: focusItem.title = "Pause focus · \(focus.countdown)"
        case .paused: focusItem.title = "Resume focus · \(focus.countdown)"
        }
        endFocusItem.isHidden = focus.timer.phase == .idle
        quietItem.title = focus.isQuiet ? "End quiet · \(focus.quietMinutes)m left" : "Quiet for 30 minutes"
        robotItem.state = state.isRobotVisible ? .on : .off
        notchItem.state = state.isNotchVisible ? .on : .off
    }

    @objc private func toggleFocus() {
        switch focus.timer.phase {
        case .idle, .completed: focus.startFocus(minutes: 25)
        case .running: focus.pauseFocus()
        case .paused: focus.resumeFocus()
        }
    }
    @objc private func endFocus() { focus.endFocus() }
    @objc private func toggleQuiet() {
        if focus.isQuiet { focus.endQuiet() } else { focus.quiet(forMinutes: 30) }
    }
    @objc private func toggleRobot() { state.isRobotVisible.toggle() }
    @objc private func showRimLight() { RimLightPreviewController.shared.show(state: state) }
    @objc private func showWatchSettings() { state.showWatchSettings?() }
    @objc private func toggleNotch() { state.isNotchVisible.toggle() }
    @objc private func resetRobot() {
        state.isRobotVisible = true
        robot.resetPosition()
    }
    @objc private func quit() { state.quit() }
}
