import MarshalCore
import SwiftUI

/// Timer controls stay on one line, leaving the width of the island to chats.
struct NotchFocusBar: View {
    @EnvironmentObject private var focus: FocusCoordinator

    private var completed: Bool { focus.timer.phase == .completed }
    private var tint: Color { completed ? RobotPalette.done : MarshalTheme.focus }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: completed ? "checkmark.circle.fill" : "scope")
                .font(.system(size: 14))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            if focus.timer.phase == .idle {
                Text("Focus").font(.system(size: 12, weight: .medium))
                Spacer(minLength: 8)
                ForEach([25, 45, 60], id: \.self) { minutes in
                    Button { focus.startFocus(minutes: minutes) } label: {
                        Text("\(minutes) min")
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(minutes == 25 ? tint.opacity(0.18) : .white.opacity(0.06), in: Capsule())
                    }
                    .accessibilityLabel("Start \(minutes) minute focus")
                }
            } else {
                Text(completed ? "Focus complete" : "Focus")
                    .font(.system(size: 12, weight: .medium))
                if !completed {
                    Text(focus.countdown)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .accessibilityLabel("\(focus.countdown) remaining")
                    if focus.timer.phase == .paused {
                        Text("Paused").foregroundStyle(.white.opacity(0.5))
                    }
                }
                Spacer(minLength: 8)
                if completed {
                    Button { focus.startFocus(minutes: Int(focus.timer.duration / 60)) } label: {
                        Label("Again", systemImage: "arrow.clockwise")
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(.white.opacity(0.08), in: Capsule())
                    }
                    .help("Start another \(Int(focus.timer.duration / 60)) minute session")
                    Button("Done") { focus.endFocus() }
                        .padding(.horizontal, 6).frame(height: 26)
                } else {
                    Button {
                        if focus.isFocusing { focus.pauseFocus() } else { focus.resumeFocus() }
                    } label: {
                        Label(focus.isFocusing ? "Pause" : "Resume", systemImage: focus.isFocusing ? "pause.fill" : "play.fill")
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(.white.opacity(0.08), in: Capsule())
                    }
                    .accessibilityLabel(focus.isFocusing ? "Pause focus" : "Resume focus")
                    Button("End") { focus.endFocus() }
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 6).frame(height: 26)
                        .accessibilityLabel("End focus")
                }
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(0.9))
        .lineLimit(1)
        .frame(height: 28)
    }
}
