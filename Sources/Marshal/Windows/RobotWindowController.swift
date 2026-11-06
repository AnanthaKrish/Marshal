import AppKit
import Combine
import MarshalCore
import SwiftUI

/// Lets a SwiftUI view move the window it lives in.
@MainActor
protocol PanelMover: AnyObject {
    var currentOrigin: CGPoint { get }
    func move(to origin: CGPoint)
    func endMove()
}

/// Owns the floating robot panel: placement, persistence, expand/collapse.
@MainActor
final class RobotWindowController: PanelMover {
    static let collapsedSize = CGSize(width: 104, height: 100)
    static let expandedSize = CGSize(width: 380, height: 440)
    /// Time the SwiftUI collapse animation needs before the window may shrink.
    private static let collapseDelay: TimeInterval = 0.3
    private static let originKey = "marshal.robot.origin"

    let panel: FloatingPanel
    private let state: MarshalState
    private var cancellables = Set<AnyCancellable>()
    private var collapseTask: Task<Void, Never>?

    init(state: MarshalState, agents: AgentSessionStore, vitals: VitalsMonitor, focus: FocusCoordinator, usage: UsageStore, watch: WatchStore) {
        self.state = state

        let origin = Self.savedOrigin() ?? Self.defaultOrigin()
        panel = FloatingPanel(
            contentRect: NSRect(origin: origin, size: Self.collapsedSize),
            level: .floating
        )

        let root = RobotWidgetView(mover: self)
            .environmentObject(state)
            .environmentObject(agents)
            .environmentObject(vitals)
            .environmentObject(focus)
            .environmentObject(usage)
            .environmentObject(watch)
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        state.$isRobotExpanded
            .removeDuplicates()
            .sink { [weak self] expanded in self?.setExpanded(expanded) }
            .store(in: &cancellables)

        state.$isRobotVisible
            .sink { [weak self] visible in self?.setVisible(visible) }
            .store(in: &cancellables)
    }

    // MARK: Visibility

    private func setVisible(_ visible: Bool) {
        if visible {
            panel.orderFrontRegardless()
        } else {
            state.isRobotExpanded = false
            panel.orderOut(nil)
        }
    }

    // MARK: Expand / collapse

    /// The robot is drawn top-centre of the content in both states, so the
    /// window grows downward and sideways around it and the robot stays put.
    private func setExpanded(_ expanded: Bool) {
        collapseTask?.cancel()
        let current = panel.frame
        var target = expanded ? Self.expandedSize : Self.collapsedSize
        if expanded, let screen = panel.screen ?? NSScreen.main {
            target.height = min(target.height, screen.visibleFrame.height - 16)
        }
        var frame = NSRect(
            x: current.midX - target.width / 2,
            y: current.maxY - target.height,
            width: target.width,
            height: target.height
        )
        if let screen = panel.screen ?? NSScreen.main {
            frame = frame.clamped(to: screen.visibleFrame)
        }

        if expanded {
            panel.setFrame(frame, display: true)
        } else {
            // Let the card animate away first, then shrink the window.
            collapseTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.collapseDelay))
                guard !Task.isCancelled, let self else { return }
                self.panel.setFrame(frame, display: true)
                self.persistOrigin()
            }
        }
    }

    // MARK: PanelMover

    var currentOrigin: CGPoint { panel.frame.origin }

    func move(to origin: CGPoint) {
        panel.setFrameOrigin(origin)
    }

    func endMove() {
        if let screen = panel.screen ?? NSScreen.main {
            let clamped = panel.frame.clamped(to: screen.visibleFrame)
            if clamped != panel.frame {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    panel.animator().setFrame(clamped, display: true)
                }
            }
        }
        persistOrigin()
    }

    func resetPosition() {
        state.isRobotExpanded = false
        let frame = NSRect(origin: Self.defaultOrigin(), size: Self.collapsedSize)
        panel.setFrame(frame, display: true)
        persistOrigin()
    }

    // MARK: Persistence

    private func persistOrigin() {
        // Always store the collapsed-equivalent origin so the robot reappears
        // where it was, regardless of which state we quit in.
        let frame = panel.frame
        let origin = CGPoint(
            x: frame.midX - Self.collapsedSize.width / 2,
            y: frame.maxY - Self.collapsedSize.height
        )
        UserDefaults.standard.set([origin.x, origin.y], forKey: Self.originKey)
    }

    private static func savedOrigin() -> CGPoint? {
        guard let values = UserDefaults.standard.array(forKey: originKey) as? [Double],
              values.count == 2 else { return nil }
        let origin = CGPoint(x: values[0], y: values[1])
        let frame = NSRect(origin: origin, size: collapsedSize)
        // Ignore a saved position that is no longer on any screen.
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        return onScreen ? origin : nil
    }

    private static func defaultOrigin() -> CGPoint {
        guard let screen = NSScreen.main else { return CGPoint(x: 100, y: 100) }
        let visible = screen.visibleFrame
        let margin: CGFloat = 28
        return CGPoint(
            x: visible.maxX - collapsedSize.width - margin,
            y: visible.minY + margin
        )
    }
}
