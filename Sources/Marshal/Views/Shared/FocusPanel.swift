import MarshalCore
import SwiftUI

enum MarshalTheme {
    static let focus = Color(red: 0.58, green: 0.49, blue: 1)
}

struct FocusMenuItems: View {
    @EnvironmentObject private var focus: FocusCoordinator
    var body: some View {
        if focus.timer.phase == .running {
            Button("Pause focus · \(focus.countdown)") { focus.pauseFocus() }
        } else if focus.timer.phase == .paused {
            Button("Resume focus · \(focus.countdown)") { focus.resumeFocus() }
        } else {
            ForEach([25, 45, 60], id: \.self) { minutes in
                Button("Focus for \(minutes) minutes") { focus.startFocus(minutes: minutes) }
            }
        }
        if focus.timer.phase != .idle {
            Button("End focus") { focus.endFocus() }
        }
        Divider()
        if focus.isQuiet {
            Button("End quiet · \(focus.quietMinutes)m left") { focus.endQuiet() }
        } else {
            ForEach([15, 30, 60], id: \.self) { minutes in
                Button("Quiet for \(minutes) minutes") { focus.quiet(forMinutes: minutes) }
            }
        }
    }
}

/// The same timer and actions in either surface. No state is owned by the view.
struct FocusPanel: View {
    var style: SurfaceStyle
    @EnvironmentObject private var focus: FocusCoordinator
    private var tint: Color { focus.timer.phase == .completed ? RobotPalette.done : MarshalTheme.focus }

    var body: some View {
        HStack(spacing: style == .notch ? 4 : 10) {
            if focus.timer.phase == .idle {
                Label("Focus", systemImage: "scope")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(style.primary)
                    .fixedSize()
                ForEach([25, 45, 60], id: \.self) { minutes in
                    Button { focus.startFocus(minutes: minutes) } label: {
                        Text("\(minutes)m")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .background(minutes == 25 ? tint.opacity(0.25) : style.primary.opacity(0.06),
                                        in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(style.primary)
                    .accessibilityLabel("Start \(minutes) minute focus")
                }
            } else {
                ZStack {
                    Circle().stroke(style.primary.opacity(0.08), lineWidth: 2)
                    Circle().trim(from: 0, to: focus.timer.progress(at: focus.now))
                        .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: focus.timer.phase == .completed ? "checkmark" : "scope")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(tint)
                }
                .frame(width: style == .notch ? 24 : 28, height: 28)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(focus.timer.phase == .paused ? "Focus · paused" : "Focus")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(style.secondary)
                    Text(focus.timer.phase == .completed ? "Complete" : focus.countdown)
                        .font(.system(size: focus.timer.phase == .completed ? 16 : style == .notch ? 21 : 23, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(style.primary)
                        .accessibilityLabel(focus.timer.phase == .completed ? "Focus complete" : "\(focus.countdown) remaining")
                }
                .fixedSize()
                Spacer(minLength: 0)
                if focus.timer.phase == .completed {
                    Button { focus.startFocus(minutes: Int(focus.timer.duration / 60)) } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: style == .notch ? 24 : 28, height: 28)
                            .background(style.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                    }
                    .help("Start another \(Int(focus.timer.duration / 60)) minute session")
                    .accessibilityLabel("Start another \(Int(focus.timer.duration / 60)) minute session")
                    Button("Done") { focus.endFocus() }
                        .fixedSize()
                } else {
                    Button {
                        if focus.isFocusing { focus.pauseFocus() } else { focus.resumeFocus() }
                    } label: {
                        Image(systemName: focus.isFocusing ? "pause.fill" : "play.fill")
                            .frame(width: style == .notch ? 24 : 28, height: 28)
                            .background(style.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                    }
                    .help(focus.isFocusing ? "Pause focus" : "Resume focus")
                    .accessibilityLabel(focus.isFocusing ? "Pause focus" : "Resume focus")
                    Button("End") { focus.endFocus() }
                        .fixedSize()
                        .help("End this focus session")
                }
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(style.secondary)
        .padding(10)
        .background(tint.opacity(style == .notch ? 0.12 : 0.08),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.16)))
    }
}

struct QuietControl: View {
    var style: SurfaceStyle
    @EnvironmentObject private var focus: FocusCoordinator

    var body: some View {
        Menu {
            if focus.isQuiet {
                Button("End quiet mode") { focus.endQuiet() }
                Divider()
            }
            ForEach([15, 30, 60], id: \.self) { minutes in
                Button("Quiet for \(minutes) minutes") { focus.quiet(forMinutes: minutes) }
            }
        } label: {
            Label(focus.isQuiet ? "Quiet · \(focus.quietMinutes)m" : "Quiet",
                  systemImage: focus.isQuiet ? "moon.fill" : "moon")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(focus.isQuiet ? MarshalTheme.focus : style.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(style.primary.opacity(0.06), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Pause nudges; your focus timer and agent tracking keep running")
    }
}

/// Common overflow menu keeps maintenance actions out of the main workflow.
struct PanelOptions: View {
    var style: SurfaceStyle
    @EnvironmentObject private var state: MarshalState
    @EnvironmentObject private var focus: FocusCoordinator

    var body: some View {
        StableMenuButton(style: style) {
            PanelOptionsMenu.make(state: state, focus: focus)
        }
        .frame(width: 26, height: 26)
    }
}
