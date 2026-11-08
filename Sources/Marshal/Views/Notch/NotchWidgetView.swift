import MarshalCore
import SwiftUI

/// Root view of the notch panel. Collapsed, it hugs the physical notch and
/// shows a pair of eyes peeking out below it. Expanded, a wide black island
/// drops down with the clock, the agent list and a few buttons inside.
struct NotchWidgetView: View {
    @EnvironmentObject private var state: MarshalState
    @EnvironmentObject private var store: NotchGeometryStore
    @EnvironmentObject private var agents: AgentSessionStore
    @EnvironmentObject private var vitalsMonitor: VitalsMonitor
    @EnvironmentObject private var focus: FocusCoordinator
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.isSnapshot) private var isSnapshot
    private var reduceMotion: Bool { systemReduceMotion || isSnapshot }
    @State private var isHovered = false

    private var geometry: NotchGeometry { store.geometry }
    private var expanded: Bool { state.isNotchExpanded }

    private var shapeWidth: CGFloat {
        if expanded {
            return NotchWindowController.expandedSize(for: geometry, hasNudge: focus.nudge != nil).width - 2 * NotchWindowController.shadowMargin
        }
        return geometry.width + 2 * NotchShape.collapsedFlare
    }

    private var shapeHeight: CGFloat {
        if expanded {
            return geometry.height + NotchWindowController.bodyHeight(hasNudge: focus.nudge != nil)
        }
        return geometry.height + NotchWindowController.peekHeight + (isHovered ? 4 : 0)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { state.isNotchExpanded = false }

            NotchShape(
                flare: expanded ? NotchShape.expandedFlare : NotchShape.collapsedFlare,
                bottomRadius: expanded ? 22 : 12
            )
            .fill(.black)
            .frame(width: shapeWidth, height: shapeHeight)
            .overlay(alignment: .top) { content }
            .clipShape(
                NotchShape(
                    flare: expanded ? NotchShape.expandedFlare : NotchShape.collapsedFlare,
                    bottomRadius: expanded ? 22 : 12
                )
            )
            .shadow(color: .black.opacity(0.10), radius: expanded ? 4 : 2, y: 2)
            .overlay {
                NotchBorder(
                    light: activityLight,
                    flare: expanded ? NotchShape.expandedFlare : NotchShape.collapsedFlare,
                    bottomRadius: expanded ? 22 : 12,
                    expanded: expanded,
                    hovered: isHovered,
                    animates: !reduceMotion && !focus.isQuiet && state.isNotchVisible
                )
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .help(expanded ? "" : "Click to open Marshal")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: expanded)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isHovered)
    }

    private var activityLight: ActivityLight {
        let look = VitalsLook.derive(conditions: vitalsMonitor.conditions,
                                     mood: focus.presentationMood, isCelebrating: focus.isCelebrating)
        return ActivityLight(signal: focus.activity, skin: state.skin, heat: look.heat)
    }

    @ViewBuilder
    private var content: some View {
        if expanded {
            ExpandedNotchContent(notchHeight: geometry.height)
                .frame(width: shapeWidth, height: shapeHeight)
                .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
            PeekEyes(
                stripWidth: shapeWidth,
                bright: isHovered,
                isScanning: agents.anyWorking && !focus.isQuiet && !reduceMotion,
                focusText: focus.timer.phase == .running || focus.timer.phase == .paused ? focus.countdown : nil,
                isPaused: focus.timer.phase == .paused,
                label: peekLabel,
                labelColor: peekLabelColor
            )
            // Keep the eyes and labels inside the strip, clear of the new rim.
            .padding(.bottom, 2)
            .frame(width: shapeWidth, height: shapeHeight, alignment: .bottom)
            .contentShape(Rectangle())
            .onTapGesture { state.toggleNotchExpanded() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Open Marshal. \(focus.timer.phase == .idle ? "" : focus.countdown + " remaining.") \(peekLabel ?? "")")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { state.toggleNotchExpanded() }
            .transition(.opacity)
        }
    }

    /// "1 needs you" / "N need you" for permission requests and errors,
    /// else "N waiting" for agents waiting on input, else nothing.
    private var agentLabel: String? {
        let needsYou = agents.needsYouCount
        if needsYou > 0 {
            return needsYou == 1 ? "1 needs you" : "\(needsYou) need you"
        }
        let waiting = agents.waitingCount
        return waiting > 0 ? "\(waiting) waiting" : nil
    }

    /// `Hot: Xcode`, `Mem 34/36` or `Battery 8%` when no agent label applies.
    private var vitalsLabel: (text: String, isAlert: Bool)? {
        NotchVitalsLabel.label(
            conditions: vitalsMonitor.conditions,
            vitals: vitalsMonitor.vitals,
            isDemo: vitalsMonitor.override != nil
        )
    }

    /// The agent label wins; the vitals label fills in when there is none.
    private var peekLabel: String? {
        if focus.isQuiet { return "Quiet \(focus.quietMinutes)m" }
        if agents.needsYouCount > 0 { return agentLabel }
        switch focus.nudge?.kind {
        case .vitals: return vitalsLabel?.text
        case .focusFinished: return "Nice focus"
        case .takeBreak: return "Stretch?"
        case .watchGentle, .watchFirm: return "Screen break?"
        default: return agentLabel ?? vitalsLabel?.text
        }
    }

    private var peekLabelColor: Color {
        if focus.isQuiet { return activityLight.color }
        if agents.needsYouCount == 0, focus.nudge?.kind == .focusFinished || focus.nudge?.kind == .takeBreak ||
            focus.nudge?.kind == .watchGentle || focus.nudge?.kind == .watchFirm {
            return activityLight.color
        }
        if agentLabel == nil, let vitals = vitalsLabel {
            return vitals.isAlert ? RobotPalette.alert : RobotPalette.attention
        }
        if agents.needsYouCount > 0 {
            return agents.currentSessions.contains { $0.state == .error } ? RobotPalette.alert : RobotPalette.attention
        }
        return RobotPalette.attention.opacity(0.8)
    }
}

/// Two tiny eyes in the strip just below the physical notch, with an
/// optional short status label at the right-hand end of the strip.
private struct PeekEyes: View {
    @EnvironmentObject private var state: MarshalState
    @EnvironmentObject private var vitalsMonitor: VitalsMonitor
    private var eyeColor: Color { state.skin.eye }
    /// How far the eye pair travels at full sweep while scanning.
    static let scanReach: CGFloat = 8
    static let eyeWidth: CGFloat = 7
    static let eyeSpacing: CGFloat = 8
    /// Half the eye pair's width plus its scan reach: the furthest an eye
    /// edge gets from the strip's centre.
    static let eyeHalfSpan: CGFloat = eyeWidth + eyeSpacing / 2 + scanReach
    /// The shape's flare sits outside the visible strip.
    static let labelTrailingInset: CGFloat = NotchShape.collapsedFlare + 10

    /// The width of the whole collapsed shape, flares included.
    var stripWidth: CGFloat
    var bright: Bool
    var isScanning: Bool
    var focusText: String?
    var isPaused: Bool
    var label: String?
    var labelColor: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isScanning)) { context in
            eyes.offset(x: isScanning ? RobotBrain.scanX(at: context.date) * Self.scanReach : 0)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottomLeading) {
            if let focusText {
                HStack(spacing: 3) {
                    Image(systemName: isPaused ? "pause.fill" : "scope")
                        .font(.system(size: 8))
                    Text(focusText).monospacedDigit()
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(MarshalTheme.focus)
                .padding(.leading, Self.labelTrailingInset)
                .padding(.bottom, 1)
            }
        }
        // An overlay so the label never moves the eyes. The eyes sit on the
        // bottom edge, so the label is bottom-aligned to stay inside the strip.
        .overlay(alignment: .bottomTrailing) {
            if let label {
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Never reaches the eyes: a long process name truncates.
                    .frame(maxWidth: maxLabelWidth, alignment: .trailing)
                    .padding(.trailing, Self.labelTrailingInset)
                    .padding(.bottom, 1)
            }
        }
    }

    /// The room right of the eyes, with an 8 pt gap.
    private var maxLabelWidth: CGFloat {
        max(0, stripWidth / 2 - (Self.eyeHalfSpan + 8) - Self.labelTrailingInset)
    }

    private var eyes: some View {
        HStack(spacing: Self.eyeSpacing) {
            eye
            eye
        }
        .opacity(bright ? 1 : 0.75)
    }

    /// Squinting when overheated, heavy-lidded when sleepy.
    private var eyeHeight: CGFloat {
        let conditions = vitalsMonitor.conditions
        if conditions.contains(.overheated) { return 4 * 0.45 }
        if conditions.contains(.sleepy) { return 4 * 0.6 }
        return 4
    }

    private var eye: some View {
        Capsule()
            .fill(eyeColor)
            .frame(width: Self.eyeWidth, height: eyeHeight)
            .shadow(color: eyeColor.opacity(bright ? 0.9 : 0.5), radius: bright ? 4 : 2)
    }
}

/// A compact vertical flow: controls, full-width chats, then a quiet status line.
private struct ExpandedNotchContent: View {
    var notchHeight: CGFloat
    @EnvironmentObject private var state: MarshalState
    @EnvironmentObject private var focus: FocusCoordinator

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text("Marshal")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    QuietControl(style: .notch)
                    PanelOptions(style: .notch)
                    Button { state.isNotchExpanded = false } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                            .frame(width: 24, height: 26).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.6))
                    .accessibilityLabel("Close notch panel")
                }
                .fixedSize(horizontal: false, vertical: true)
                NudgeBanner(style: .notch)
                NotchFocusBar()
                    .fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(.white.opacity(0.09)).frame(height: 1)
                ActivityDetailsView(style: .notch)
                SystemHealthView(style: .notch)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .environment(\.colorScheme, .dark)
    }
}
