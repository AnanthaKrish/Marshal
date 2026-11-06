import MarshalCore
import SwiftUI

struct NudgeBanner: View {
    var style: SurfaceStyle
    @EnvironmentObject private var focus: FocusCoordinator
    @EnvironmentObject private var agents: AgentSessionStore
    @EnvironmentObject private var state: MarshalState
    @EnvironmentObject private var watch: WatchStore

    var body: some View {
        if let nudge = focus.nudge {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: symbol(nudge.kind))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint(nudge.kind))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(nudge.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(style.primary)
                    Text(nudge.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(style.secondary)
                        .lineLimit(1)
                }
                .lineLimit(1)
                .help(nudge.title + " · " + nudge.detail)
                Spacer(minLength: 0)
                Group {
                    if nudge.kind == .takeBreak {
                        HStack(spacing: 8) {
                            Button("Done") { focus.acknowledgeBreak() }
                            Button("10m") { focus.snoozeBreak() }
                                .help("Remind me in 10 minutes")
                                .accessibilityLabel("Remind me in 10 minutes")
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint(nudge.kind))

                    } else if nudge.kind == .watchGentle || nudge.kind == .watchFirm {
                        HStack(spacing: 8) {
                            Button("Done") { watch.reset() }.help("Start a fresh watch-time session")
                            Button("10m") { watch.snooze() }
                                .help("Snooze watch reminders for 10 minutes")
                                .accessibilityLabel("Snooze watch reminders for 10 minutes")
                        }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint(nudge.kind))
                    } else if let id = nudge.sessionID,
                              let session = agents.sessions.first(where: { $0.id == id }), AppOpener.canOpen(session) {
                        Button("Open ↗") {
                            AppOpener.open(session)
                            state.collapseAll()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint(nudge.kind))
                        .help("Open in \(AppOpener.appName(for: session) ?? "app")")
                        .accessibilityLabel("Open in \(AppOpener.appName(for: session) ?? "app")")
                    }
                }
                .fixedSize()
                Button { focus.dismissNudge() } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(style.secondary)
                .accessibilityLabel("Dismiss nudge")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint(nudge.kind).opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tint(_ kind: AttentionRequest.Kind) -> Color {
        switch kind {
        case .error, .vitals: RobotPalette.alert
        case .permission, .watchFirm: RobotPalette.attention
        case .focusFinished, .agentFinished: RobotPalette.done
        case .takeBreak, .watchGentle: MarshalTheme.focus
        }
    }

    private func symbol(_ kind: AttentionRequest.Kind) -> String {
        switch kind {
        case .error: "exclamationmark.bubble"
        case .permission: "hand.raised"
        case .vitals: "waveform.path.ecg"
        case .focusFinished, .agentFinished: "checkmark.circle"
        case .takeBreak: "cup.and.saucer"
        case .watchGentle, .watchFirm: "play.rectangle"
        }
    }
}
