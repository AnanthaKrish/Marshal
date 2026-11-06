import MarshalCore
import SwiftUI

struct ActivityDetailsView: View {
    var style: SurfaceStyle
    @EnvironmentObject private var state: MarshalState
    @EnvironmentObject private var agents: AgentSessionStore
    @EnvironmentObject private var usage: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: style == .notch ? 4 : 6) {
            HStack(spacing: 12) {
                tab("Chats\(agents.sessions.isEmpty ? "" : " · \(agents.sessions.count)")", selection: .chats)
                tab("Usage", selection: .usage)
                if FeatureAvailability.watchTime { tab("Watch", selection: .watch) }
                Spacer(minLength: 0)
                if state.detailTab == .chats, agents.sessions.contains(where: { $0.state == .done }) {
                    Button("Clear finished") { agents.clearFinished() }
                        .buttonStyle(.plain)
                        .foregroundStyle(style.secondary)
                } else if state.detailTab == .usage {
                    Button { state.refreshUsage?() } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 22, height: 16)
                    }
                    .buttonStyle(.plain).foregroundStyle(style.secondary)
                    .disabled(usage.isRefreshing)
                    .help("Refresh Codex limits. Claude updates from its active sessions.")
                    .accessibilityLabel("Refresh usage")
                }
            }
            .font(.system(size: style == .notch ? 10 : 11, weight: .medium))
            .frame(height: style == .notch ? 14 : 18)
            if state.detailTab == .chats {
                SessionListView(style: style, fillsAvailableHeight: true, showsHeader: false)
            } else if FeatureAvailability.watchTime, state.detailTab == .watch {
                WatchPanel(style: style)
            } else {
                UsageListView(style: style)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func tab(_ title: String, selection: MarshalState.DetailTab) -> some View {
        Button { state.detailTab = selection } label: {
            Text(title).fontWeight(state.detailTab == selection ? .semibold : .regular)
                .foregroundStyle(state.detailTab == selection ? style.primary : style.secondary)
                .padding(.bottom, 3)
                .overlay(alignment: .bottom) {
                    if state.detailTab == selection {
                        Capsule().fill(style.primary.opacity(0.65)).frame(height: 1.5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(state.detailTab == selection ? [.isSelected] : [])
    }
}

struct UsageListView: View {
    var style: SurfaceStyle
    @EnvironmentObject private var usage: UsageStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            ScrollView {
                VStack(spacing: 4) {
                    provider("claude-code", name: "Claude", now: timeline.date)
                    provider("codex", name: "Codex", now: timeline.date)
                }
            }
            .scrollIndicators(.visible)
        }
        .frame(maxHeight: .infinity)
    }

    private func provider(_ agent: String, name: String, now: Date) -> some View {
        let sample = usage.providers[agent]
        let stale = sample?.isStale(at: now) ?? true
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    AgentBadge(agent: agent, size: 13)
                    Text(name).font(.system(size: 11, weight: .semibold))
                }
                Text(sample.map { "\(stale ? "Last " : "")\(UsageText.age($0.updatedAt, now: now))" } ?? "No reading")
                    .font(.system(size: 8)).foregroundStyle(style.secondary)
            }
            .frame(width: style == .notch ? 67 : 65, alignment: .leading)
            if let sample, !sample.windows.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    // Two windows per row; additional account buckets remain reachable.
                    ForEach(Array(stride(from: 0, to: sample.windows.count, by: 2)), id: \.self) { start in
                        HStack(spacing: 10) {
                            ForEach(Array(sample.windows[start..<min(start + 2, sample.windows.count)])) { window in
                                limit(window, stale: stale, now: now)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(usage.messages[agent] ?? (agent == "claude-code" ? "Waiting for a Claude Code reading" : "Checking Codex limits…"))
                    .font(.system(size: 10)).foregroundStyle(style.secondary)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(style.primary)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(minHeight: 40)
        .background(style.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        .help(usage.messages[agent] ?? (stale ? "Last reported reading; usage may have changed." : "Account allowance, separate from each chat's context size."))
    }

    private func limit(_ window: UsageWindow, stale: Bool, now: Date) -> some View {
        let expired = window.hasReset(at: now)
        let color = UsageColors.color(stale || expired ? .unknown : .forUsedPercent(window.usedPercent), style: style)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text(window.title).foregroundStyle(style.secondary)
                Spacer(minLength: 0)
                Text(expired ? "—" : "\(Int((100 - window.usedPercent).rounded()))% left")
                    .foregroundStyle(color).monospacedDigit()
            }
            .font(.system(size: 10, weight: .medium))
            .lineLimit(1)
            GeometryReader { geometry in
                Capsule().fill(style.primary.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule().fill(color)
                            .frame(width: geometry.size.width * (expired ? 0 : max(0, 100 - window.usedPercent) / 100))
                    }
            }.frame(height: 2)
            Text(expired ? "Awaiting refresh" : UsageText.reset(window.resetsAt, now: now))
                .font(.system(size: 8)).foregroundStyle(style.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .help("\(window.title): \(Int(window.usedPercent.rounded()))% used.\(stale ? " Last reported; may be out of date." : "")")
    }
}

struct ContextUsageBadge: View {
    var value: ContextUsage?
    var style: SurfaceStyle
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let stale = value?.isStale(at: timeline.date) ?? false
            Text(value.map { "Ctx \($0.isEstimate ? "≈" : "")\(Int($0.usedPercent.rounded()))%" } ?? "Ctx —")
                .font(.system(size: 9, weight: .medium)).monospacedDigit()
                .foregroundStyle(UsageColors.color(stale ? .unknown : .forUsedPercent(value?.usedPercent), style: style))
                .fixedSize()
                .help(help(stale: stale))
                .accessibilityLabel(value.map { "Context \($0.isEstimate ? "approximately " : "")\(Int($0.usedPercent.rounded())) percent used\(stale ? ", last reported" : "")" } ?? "Context usage unavailable")
        }
    }
    private func help(stale: Bool) -> String {
        guard let value else { return "Context usage hasn't been reported for this chat." }
        var text = "\(value.isEstimate ? "Estimated context" : "Context"): \(Int(value.usedPercent.rounded()))% used"
        if let used = value.usedTokens, let capacity = value.capacity {
            text += " · \(used.formatted()) / \(capacity.formatted()) tokens"
        } else if let capacity = value.capacity {
            text += " · \(capacity.formatted()) token window"
        }
        return text + (stale ? ". Last reported; may be out of date." : ". Based on the latest reported response.")
    }
}

enum UsageColors {
    static func color(_ level: UsageLevel, style: SurfaceStyle) -> Color {
        switch level {
        case .healthy: style == .notch ? RobotPalette.working : Color(red: 0.05, green: 0.48, blue: 0.25)
        case .caution: style == .notch ? RobotPalette.attention : Color(red: 0.65, green: 0.37, blue: 0)
        case .critical: style == .notch ? RobotPalette.alert : Color(red: 0.78, green: 0.14, blue: 0.18)
        case .unknown: style.secondary
        }
    }
}

enum UsageText {
    static func age(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }
    static func reset(_ date: Date?, now: Date) -> String {
        guard let date else { return "Reset unknown" }
        let minutes = max(0, Int(ceil(date.timeIntervalSince(now) / 60)))
        if minutes >= 1440 { return "Resets in \(minutes / 1440)d \((minutes % 1440) / 60)h" }
        if minutes >= 60 { return "Resets in \(minutes / 60)h \(minutes % 60)m" }
        return "Resets in \(minutes)m"
    }
}
