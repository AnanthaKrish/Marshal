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
    @State private var installations: [HookAgent: HookInstaller.Installation] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(agents.serverError.map { "Marshal can't listen for agents: \($0)" }
                 ?? (installations.values.contains { $0 == .ready }
                     ? "Waiting for activity. Start a new chat in a connected app."
                     : "Connect your agents to see their chats here."))
                .lineLimit(3)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(style.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { setupButtons }
                VStack(alignment: .leading, spacing: 8) { setupButtons }
            }
        }
        .task { refreshInstallations() }
        .onReceive(NotificationCenter.default.publisher(for: SetupPresenter.didChange)) { _ in refreshInstallations() }
    }

    private func refreshInstallations() {
        installations = Dictionary(uniqueKeysWithValues: HookAgent.allCases.map { ($0, HookInstaller.installation(for: $0)) })
    }

    private func title(_ agent: HookAgent) -> String {
        switch installations[agent] ?? .missing {
        case .ready: "\(agent.displayName) · Waiting"
        case .needsUpdate: "Update \(agent.displayName)"
        case .unreadable: "Check \(agent.displayName)"
        case .missing: "Set up \(agent.displayName)"
        }
    }

    @ViewBuilder
    private var setupButtons: some View {
        ForEach(HookAgent.allCases, id: \.self) { agent in
            QuickActionButton(title: title(agent), systemImage: AgentBadge.glyph(for: agent.rawValue), style: style) {
                SetupPresenter.install(agent)
            }
            .fixedSize(horizontal: true, vertical: false)
            .help(installations[agent] == .ready ? "Hooks installed; waiting for the first event. Click to check setup." : "Set up or repair this integration.")
        }
    }
}
