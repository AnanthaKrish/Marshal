import MarshalCore
import SwiftUI

/// One agent session as a two-line card: badge, title and elapsed time on
/// top; state pill, message and project below. Click fronts the agent's app;
/// right-click offers Open and Dismiss.
struct SessionCard: View {
    var session: AgentSession
    var style: SurfaceStyle
    /// Shows the "Open ↗" chip without hovering. Only for `--snapshot`, which
    /// cannot render hover.
    var showsOpenAlways = false

    @EnvironmentObject private var agents: AgentSessionStore
    @EnvironmentObject private var state: MarshalState
    @EnvironmentObject private var usage: UsageStore
    @State private var isHovered = false

    var body: some View {
        let canOpen = AppOpener.canOpen(session)
        let showsChip = canOpen
        Group {
            if canOpen {
                Button {
                    AppOpener.open(session)
                    state.collapseAll()
                } label: { row(showsChip: showsChip) }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(session.title ?? session.agent) in \(AppOpener.appName(for: session) ?? "app"). \(StatePill.label(for: session.state))")
            } else {
                row(showsChip: false)
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .openHelp(canOpen ? AppOpener.appName(for: session) : nil)
        .contextMenu {
            if canOpen {
                Button("Open") { AppOpener.open(session); state.collapseAll() }
            }
            Button("Dismiss") { agents.dismiss(session.id) }
        }
    }

    @ViewBuilder
    private func row(showsChip: Bool) -> some View {
        if style == .notch {
            notchRow(showsChip: showsChip)
        } else {
            cardRow(showsChip: showsChip)
        }
    }

    /// Full-width rows give the title room and keep the action in one stable column.
    private func notchRow(showsChip: Bool) -> some View {
        HStack(spacing: 9) {
            AgentBadge(agent: session.agent, size: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title ?? String(session.session.prefix(8)))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 5) {
                    Circle().fill(StatePill.tint(for: session.state, style: style))
                        .frame(width: 4, height: 4)
                    Text(StatePill.label(for: session.state))
                        .foregroundStyle(StatePill.tint(for: session.state, style: style))
                        .fixedSize()
                    if let message = session.message, !message.isEmpty {
                        Text("· \(message)").foregroundStyle(style.secondary)
                    }
                    Spacer(minLength: 0)
                    ContextUsageBadge(value: usage.contexts[session.id], style: style)
                }
                .font(.system(size: 10))
            }
            VStack(alignment: .trailing, spacing: 3) {
                if showsChip {
                    Text("Open ↗")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(isHovered ? 1 : 0.75))
                }
                ElapsedText(since: session.since)
                    .font(.system(size: 9)).foregroundStyle(style.secondary)
            }
            .fixedSize()
        }
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(height: 40)
        .background(.white.opacity(isHovered ? 0.10 : 0.035), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .help([session.title, session.project, session.message].compactMap { $0 }.joined(separator: " · "))
    }

    private func cardRow(showsChip: Bool) -> some View {
        HStack(spacing: 8) {
            AgentBadge(agent: session.agent)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.title ?? String(session.session.prefix(8)))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(style.primary)
                    Spacer(minLength: 4)
                    ContextUsageBadge(value: usage.contexts[session.id], style: style)
                    ElapsedText(since: session.since)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(style.secondary)
                }
                HStack(spacing: 5) {
                    StatePill(state: session.state, style: style)
                    detail(showsPath: !showsChip)
                    Spacer(minLength: 0)
                    if showsChip {
                        OpenChip()
                            .transition(.opacity)
                    }
                }
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Message (usually the tool name) then the shortened project path; the
    /// message keeps its room and the path truncates first. The path gives way
    /// to the Open chip while hovered.
    private func detail(showsPath: Bool) -> some View {
        HStack(spacing: 4) {
            if let message = session.message, !message.isEmpty {
                Text(message)
                    .layoutPriority(1)
            }
            if showsPath, let project = session.project, !project.isEmpty {
                let path = Self.shortPath(project)
                Text(session.message?.isEmpty == false ? "· \(path)" : path)
                    .layoutPriority(-1)
            }
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(style.secondary)
    }

    private var background: Color {
        switch style {
        case .card: Color.primary.opacity(isHovered ? 0.10 : 0.045)
        case .notch: Color.white.opacity(isHovered ? 0.14 : 0.06)
        }
    }

    /// "~/…/Marshal" for a folder under home; "/…/bar" elsewhere. Short paths
    /// ("~/Marshal", "/tmp") are left whole.
    static func shortPath(_ path: String, home: String = NSHomeDirectory()) -> String {
        var path = path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        var prefix = ""
        var rest = path
        if path == home {
            return "~"
        } else if path.hasPrefix(home + "/") {
            prefix = "~"
            rest = String(path.dropFirst(home.count))
        }
        let components = rest.split(separator: "/")
        guard components.count > 1, let last = components.last else { return prefix + rest }
        return "\(prefix)/…/\(last)"
    }

    /// "now", "2m", "1h 05m".
    static func elapsed(from start: Date, to now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        return String(format: "%dh %02dm", minutes / 60, minutes % 60)
    }
}

extension EnvironmentValues {
    /// Snapshot-only: lets `--snapshot` reach `SessionCard.showsOpenAlways`
    /// through the panels without threading a parameter through each view.
    @Entry var showsOpenChipAlways = false
}

/// Time since `since`, refreshed each minute.
struct ElapsedText: View {
    var since: Date

    var body: some View {
        // The timeline only triggers a redraw each minute; its entry dates
        // fall on minute boundaries, so read the clock directly.
        TimelineView(.everyMinute) { _ in
            Text(SessionCard.elapsed(from: since, to: .now))
                .monospacedDigit()
        }
    }
}

/// The "Open ↗" chip shown on a hovered card.
private struct OpenChip: View {
    var body: some View {
        Text("Open ↗")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .fixedSize()
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.accentColor, in: Capsule())
    }
}

/// A compact one-line session: badge, title, state dot, elapsed. Click opens.
struct SessionChip: View {
    var session: AgentSession
    var style: SurfaceStyle
    /// Called after the chip opens its app; the notch uses it to collapse.
    var onOpen: (() -> Void)? = nil

    @EnvironmentObject private var agents: AgentSessionStore
    @State private var isHovered = false

    var body: some View {
        let canOpen = AppOpener.canOpen(session)
        HStack(spacing: 6) {
            AgentBadge(agent: session.agent, size: 16)
            Text(session.title ?? String(session.session.prefix(8)))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(style.primary)
            Circle()
                .fill(StatePill.tint(for: session.state, style: style))
                .frame(width: 6, height: 6)
                .help(StatePill.label(for: session.state))
            Spacer(minLength: 4)
            ElapsedText(since: session.since)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(style.secondary)
                // The title truncates first; the elapsed time stays whole.
                .fixedSize()
        }
        .lineLimit(1)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture { open() }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .openHelp(canOpen ? AppOpener.appName(for: session) : nil)
        .contextMenu {
            if canOpen {
                Button("Open") { open() }
            }
            Button("Dismiss") { agents.dismiss(session.id) }
        }
    }

    private func open() {
        guard AppOpener.canOpen(session) else { return }
        AppOpener.open(session)
        onOpen?()
    }

    private var background: Color {
        switch style {
        case .card: Color.primary.opacity(isHovered ? 0.10 : 0.045)
        case .notch: Color.white.opacity(isHovered ? 0.14 : 0.06)
        }
    }
}

private extension View {
    /// "Open <App>" as a tooltip when the session can open; no tooltip otherwise.
    @ViewBuilder
    func openHelp(_ appName: String?) -> some View {
        if let appName {
            help("Open \(appName)")
        } else {
            self
        }
    }
}
