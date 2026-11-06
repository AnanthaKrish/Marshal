import SwiftUI
import AppKit
import MarshalCore

/// Root view of the robot panel. Collapsed, it is just the robot. Expanded, a
/// glass card unfolds underneath it. The robot is always top-centre so the
/// window can grow around it without the robot moving on screen.
struct RobotWidgetView: View {
    static let robotSize: CGFloat = 66
    /// Headroom for the beacon glow, radar rings, the bob and the hover scale.
    static let topPadding: CGFloat = 22

    let mover: PanelMover

    @EnvironmentObject private var state: MarshalState
    @EnvironmentObject private var agents: AgentSessionStore
    @EnvironmentObject private var vitalsMonitor: VitalsMonitor
    @EnvironmentObject private var focus: FocusCoordinator
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.isSnapshot) private var isSnapshot
    private var reduceMotion: Bool { systemReduceMotion || isSnapshot }
    @StateObject private var brain = RobotBrain()

    @State private var isHovered = false
    @State private var isBobbing = false
    @State private var dragStart: (mouse: CGPoint, origin: CGPoint)?
    @State private var didDrag = false
    private var isCelebrating: Bool { focus.isCelebrating }

    private var robotFrame: CGSize { PookieFigure.frameSize(for: Self.robotSize) }

    private var vitalsLook: VitalsLook {
        VitalsLook.derive(conditions: vitalsMonitor.conditions, mood: focus.presentationMood, isCelebrating: isCelebrating)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Clicking the transparent margin of the window collapses the card.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { state.isRobotExpanded = false }

            if state.isRobotExpanded {
                RobotCard(contentTopInset: robotFrame.height - PookieFigure.shoulderOffset(for: Self.robotSize) - 4)
                    .padding(.top, PookieFigure.shoulderOffset(for: Self.robotSize))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(
                        .scale(scale: 0.6, anchor: .top)
                        .combined(with: .opacity)
                    )
            }

            robot
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, Self.topPadding)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: state.isRobotExpanded)
        .onAppear {
            isBobbing = true
            brain.start(anchor: eyeScreenPosition)
        }
        .onDisappear {
            brain.stop()
        }
        .onChange(of: agents.anyWorking, initial: true) { _, working in
            brain.isScanning = working && !focus.isQuiet && !reduceMotion
        }
        .onChange(of: focus.isQuiet) { _, quiet in brain.isScanning = agents.anyWorking && !quiet && !reduceMotion }
        .onChange(of: reduceMotion) { _, reduced in brain.isScanning = agents.anyWorking && !focus.isQuiet && !reduced }
        .onChange(of: vitalsLook.sleepyLids, initial: true) { _, sleepy in
            brain.blinkScale = sleepy ? 3 : 1
        }
    }

    private var robot: some View {
        let suppressMotion = reduceMotion || focus.isQuiet || focus.nudge == nil
        let watchTap = focus.nudge?.kind == .watchFirm
        return PookieFigure(
            size: Self.robotSize,
            skin: state.skin,
            gaze: brain.gaze,
            isBlinking: brain.isBlinking,
            isHappy: state.isRobotExpanded || isHovered,
            isHovered: isHovered,
            mood: focus.presentationMood,
            isCelebrating: isCelebrating,
            completionLightStyle: state.completionLightStyle,
            lightReplay: focus.nudgePulse,
            vitals: vitalsLook,
            focusProgress: focus.timer.phase == .running || focus.timer.phase == .paused ? focus.timer.progress(at: focus.now) : nil,
            isQuiet: focus.isQuiet,
            isYawning: focus.nudge?.kind == .takeBreak || focus.isWatchYawning,
            showsFloorShadow: !state.isRobotExpanded,
            activity: focus.activity,
            animates: !focus.isQuiet && !reduceMotion
        )
        // Only the arbitration winner can request a gesture, once per occurrence.
        .keyframeAnimator(initialValue: 0.0, trigger: focus.nudgePulse) { content, motion in
            content
                .offset(x: suppressMotion || watchTap ? 0 : motion,
                        y: !suppressMotion && watchTap ? abs(motion) * 1.5 : 0)
                .rotationEffect(.degrees(suppressMotion || watchTap ? 0 : motion * 0.4), anchor: .bottom)
        } keyframes: { _ in
            SpringKeyframe(-2, duration: 0.18)
            SpringKeyframe(watchTap ? 0 : 2, duration: 0.24)
            SpringKeyframe(watchTap ? -2 : -1, duration: 0.20)
            SpringKeyframe(0, duration: 0.24)
        }
        .scaleEffect(isHovered ? 1.06 : 1)
        .offset(y: reduceMotion || focus.isQuiet ? 0 : isBobbing ? -3 : 3)
        .animation(reduceMotion || focus.isQuiet ? nil : .easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: isBobbing)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.openHand.push() } else { NSCursor.pop() }
        }
        .gesture(dragOrTap)
        .contextMenu { RobotContextMenu(mover: mover) }
        .help("Click to open Pookie. Drag to move.")
    }

    /// A single gesture that moves the window on drag and toggles on a click.
    /// Translation is measured with the global mouse location because the
    /// view itself moves with the window while dragging.
    private var dragOrTap: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { _ in
                let mouse = NSEvent.mouseLocation
                guard let start = dragStart else {
                    dragStart = (mouse, mover.currentOrigin)
                    didDrag = false
                    return
                }
                let dx = mouse.x - start.mouse.x
                let dy = mouse.y - start.mouse.y
                if !didDrag, hypot(dx, dy) < 4 { return }
                didDrag = true
                mover.move(to: CGPoint(x: start.origin.x + dx, y: start.origin.y + dy))
            }
            .onEnded { _ in
                if didDrag {
                    mover.endMove()
                } else {
                    state.toggleRobotExpanded()
                }
                dragStart = nil
                didDrag = false
            }
    }

    /// Where the eyes are in screen coordinates (for the gaze tracker).
    private func eyeScreenPosition() -> CGPoint {
        let origin = mover.currentOrigin
        let windowWidth = state.isRobotExpanded
            ? RobotWindowController.expandedSize.width
            : RobotWindowController.collapsedSize.width
        let windowHeight = state.isRobotExpanded
            ? RobotWindowController.expandedSize.height
            : RobotWindowController.collapsedSize.height
        let eyeY = Self.topPadding + Self.robotSize * PookieFigure.antennaHeight + Self.robotSize * 0.4
        return CGPoint(x: origin.x + windowWidth / 2, y: origin.y + windowHeight - eyeY)
    }
}

struct RobotContextMenu: View {
    let mover: PanelMover
    @EnvironmentObject private var state: MarshalState
    @EnvironmentObject private var agents: AgentSessionStore
    @EnvironmentObject private var vitalsMonitor: VitalsMonitor

    /// The "Try Vitals" items, each with the condition it starts from.
    private static let vitalsDemos: [(String, VitalsConditions)] = [
        ("Sweating", .sweating), ("Hot", .hot), ("Overheated", .overheated), ("Stuffed", .stuffed),
        ("Dizzy", .dizzy), ("Sleepy", .sleepy), ("Crying", .crying),
    ]

    /// Pushes a demo session through the real store so every mood can be
    /// seen without an agent.
    private func demo(_ mood: AgentState) {
        agents.apply(AgentEvent(agent: "demo", session: "demo", state: mood, title: "Demo", message: mood == .needsPermission ? "Bash" : nil))
    }

    var body: some View {
        Menu("Focus & quiet") {
            FocusMenuItems()
        }
        Button("Rim light…") { RimLightPreviewController.shared.show(state: state) }
        if FeatureAvailability.watchTime {
            Button("Watch-time reminders…") { state.showWatchSettings?() }
        }
        Divider()
        Menu("Try a Mood") {
            Button("Working") { demo(.working) }
            Button("Needs Permission") { demo(.needsPermission) }
            Button("Waiting for You") { demo(.needsInput) }
            Button("Finished") { demo(.done) }
            Button("Error") { demo(.error) }
            Divider()
            Button("Clear Demo") { demo(.ended) }
        }
        Menu("Try Vitals") {
            ForEach(Self.vitalsDemos, id: \.0) { name, base in
                let set = VitalsConditions.implied(base)
                Button {
                    vitalsMonitor.override = set
                } label: {
                    if vitalsMonitor.override == set {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(name)
                    }
                }
            }
            Divider()
            Button("Back to real") { vitalsMonitor.override = nil }
        }
        Menu("Pookie's Colour") {
            ForEach(PookieSkin.all) { skin in
                Button {
                    state.skinID = skin.id
                } label: {
                    if skin.id == state.skinID {
                        Label(skin.name, systemImage: "checkmark")
                    } else {
                        Text(skin.name)
                    }
                }
            }
        }
        Divider()
        Button(state.isNotchVisible ? "Hide Notch Widget" : "Show Notch Widget") {
            state.isNotchVisible.toggle()
        }
        Button("Reset Position") {
            (mover as? RobotWindowController)?.resetPosition()
        }
        Divider()
        Button("Hide Pookie") { state.isRobotVisible = false }
        Button("Quit Marshal") { state.quit() }
    }
}
