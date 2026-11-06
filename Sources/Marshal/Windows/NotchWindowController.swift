import AppKit
import Combine
import MarshalCore
import SwiftUI

/// Describes the physical notch (or a stand-in on screens without one).
struct NotchGeometry: Equatable {
    var width: CGFloat
    var height: CGFloat
    var hasNotch: Bool

    @MainActor
    static func measure(on screen: NSScreen) -> NotchGeometry {
        let inset = screen.safeAreaInsets.top
        if inset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            return NotchGeometry(width: width, height: inset, hasNotch: true)
        }
        // No notch: pretend there is a compact one tucked under the menu bar.
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return NotchGeometry(width: 180, height: max(menuBar, 24), hasNotch: false)
    }
}

/// Observable wrapper so the SwiftUI view re-lays out when displays change.
@MainActor
final class NotchGeometryStore: ObservableObject {
    @Published var geometry: NotchGeometry
    init(geometry: NotchGeometry) { self.geometry = geometry }
}

/// Owns the notch panel: pins it over the notch and resizes it on expand.
@MainActor
final class NotchWindowController {
    /// Transparent margin around the drawn shape so its shadow is not clipped.
    static let shadowMargin: CGFloat = 24
    static let peekHeight: CGFloat = 14
    static func bodyHeight(hasNudge: Bool) -> CGFloat { hasNudge ? 262 : 214 }
    static let minExpandedWidth: CGFloat = 480
    private static let collapseDelay: TimeInterval = 0.3

    let panel: FloatingPanel
    private let state: MarshalState
    private let focus: FocusCoordinator
    private var cancellables = Set<AnyCancellable>()
    private var collapseTask: Task<Void, Never>?
    let geometryStore: NotchGeometryStore
    private var geometry: NotchGeometry { geometryStore.geometry }
    private var screen: NSScreen

    init(state: MarshalState, agents: AgentSessionStore, vitals: VitalsMonitor, focus: FocusCoordinator, usage: UsageStore, watch: WatchStore) {
        self.state = state
        self.focus = focus
        screen = Self.preferredScreen()
        geometryStore = NotchGeometryStore(geometry: NotchGeometry.measure(on: screen))

        // Level above the menu bar so the shape visually merges with the notch.
        let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        panel = FloatingPanel(contentRect: .zero, level: level)

        let root = NotchWidgetView()
            .environmentObject(state)
            .environmentObject(geometryStore)
            .environmentObject(agents)
            .environmentObject(vitals)
            .environmentObject(focus)
            .environmentObject(usage)
            .environmentObject(watch)
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        layout(expanded: false)

        state.$isNotchExpanded
            .removeDuplicates()
            .sink { [weak self] expanded in self?.setExpanded(expanded) }
            .store(in: &cancellables)

        state.$isNotchVisible
            .sink { [weak self] visible in self?.setVisible(visible) }
            .store(in: &cancellables)

        focus.$nudge.map { $0 != nil }.removeDuplicates()
            .sink { [weak self] hasNudge in
                guard let self, self.state.isNotchExpanded else { return }
                self.layout(expanded: true, hasNudge: hasNudge)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.screenChanged() }
            .store(in: &cancellables)
    }

    // MARK: Sizes

    static func collapsedSize(for geometry: NotchGeometry) -> CGSize {
        CGSize(
            width: geometry.width + 2 * NotchShape.collapsedFlare + 2 * shadowMargin,
            height: geometry.height + peekHeight + shadowMargin
        )
    }

    static func expandedSize(for geometry: NotchGeometry, hasNudge: Bool = false) -> CGSize {
        CGSize(
            width: max(minExpandedWidth, geometry.width + 240) + 2 * shadowMargin,
            height: geometry.height + bodyHeight(hasNudge: hasNudge) + shadowMargin
        )
    }

    // MARK: Layout

    private func layout(expanded: Bool, hasNudge: Bool? = nil) {
        let size = expanded ? Self.expandedSize(for: geometry, hasNudge: hasNudge ?? (focus.nudge != nil)) : Self.collapsedSize(for: geometry)
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true)
    }

    private func setExpanded(_ expanded: Bool) {
        collapseTask?.cancel()
        if expanded {
            layout(expanded: true)
        } else {
            collapseTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.collapseDelay))
                guard !Task.isCancelled, let self else { return }
                self.layout(expanded: false)
            }
        }
    }

    private func setVisible(_ visible: Bool) {
        if visible {
            panel.orderFrontRegardless()
        } else {
            state.isNotchExpanded = false
            panel.orderOut(nil)
        }
    }

    private func screenChanged() {
        screen = Self.preferredScreen()
        let measured = NotchGeometry.measure(on: screen)
        if measured != geometry {
            geometryStore.geometry = measured
        }
        layout(expanded: state.isNotchExpanded)
    }

    /// The built-in display with a notch if there is one, else the main screen.
    private static func preferredScreen() -> NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
