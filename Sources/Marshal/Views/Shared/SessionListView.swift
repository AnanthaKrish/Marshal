import MarshalCore
import SwiftUI

/// The agents reporting to Marshal, worst state first, as cards. Click a card
/// to front its app; right-click to open or dismiss it.
struct SessionListView: View {
    var style: SurfaceStyle
    /// Let the chat list absorb the panel's remaining height; controls stay pinned.
    var fillsAvailableHeight = false
    var maxRows: Int = 3
    var showsHeader = true
    @EnvironmentObject private var agents: AgentSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: style == .notch ? 4 : 6) {
            if showsHeader { header }
            if agents.sessions.isEmpty {
                AgentsEmptyState(style: style)
            } else {
                ScrollView {
                    LazyVStack(spacing: style == .notch ? 3 : 6) {
                        ForEach(agents.sessions) { session in
                            SessionCard(session: session, style: style, showsOpenAlways: true)
                        }
                    }
                }
                .frame(height: fillsAvailableHeight ? nil : CGFloat(min(maxRows, agents.sessions.count)) * (style == .notch ? 43 : 56))
                .frame(maxHeight: fillsAvailableHeight ? .infinity : nil)
                .scrollIndicators(.visible)
            }
        }
        .frame(maxHeight: fillsAvailableHeight ? .infinity : nil, alignment: .top)
    }

    private var header: some View {
        HStack {
            Text(agents.sessions.isEmpty ? "Chats" : "Chats · \(agents.sessions.count)")
                .font(.system(size: style == .notch ? 10 : 12, weight: .semibold, design: .rounded))
                .foregroundStyle(style == .notch ? style.secondary : style.primary)
                .help("Scroll the list to see every session")
            Spacer(minLength: 0)
            if agents.sessions.contains(where: { $0.state == .done }) {
                Button("Clear finished") { agents.clearFinished() }
                    .buttonStyle(.plain)
                    .font(.system(size: style == .notch ? 10 : 11, weight: .medium, design: .rounded))
                    .foregroundStyle(style.secondary)
            }
        }
    }
}

/// What the agent list shows before any agent reports: a line of copy (or
/// the server error) and buttons that install the hooks. Shared by the robot
/// card and the notch island's focus area.
struct AgentsEmptyState: View {
    var style: SurfaceStyle
    @EnvironmentObject private var agents: AgentSessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(agents.serverError.map { "Marshal can't listen for agents: \($0)" } ?? "Your agents will appear here. Connect one to get started.")
                .lineLimit(3)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(style.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // Side by side when they fit, stacked in the narrow robot card.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { setupButtons }
                VStack(alignment: .leading, spacing: 8) { setupButtons }
            }
        }
    }

    @ViewBuilder
    private var setupButtons: some View {
        QuickActionButton(title: "Set up Claude Code", systemImage: "terminal", style: style) {
            SetupPresenter.install(.claudeCode)
        }
        .fixedSize(horizontal: true, vertical: false)
        QuickActionButton(title: "Set up Codex", systemImage: "chevron.left.forwardslash.chevron.right", style: style) {
            SetupPresenter.install(.codex)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
