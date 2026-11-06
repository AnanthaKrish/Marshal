import MarshalCore
import SwiftUI

/// Small counts under the "Agents" header, e.g. "2 working", "1 needs you".
/// Only non-zero counts are shown; tapping does nothing in this phase.
struct SummaryChips: View {
    var style: SurfaceStyle

    @EnvironmentObject private var agents: AgentSessionStore

    var body: some View {
        let items = Self.items(for: agents.sessions)
        if !items.isEmpty {
            HStack(spacing: 5) {
                ForEach(items, id: \.text) { item in
                    let tint = StatePill.tint(for: item.state, style: style)
                    Text(item.text)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                        .brightness(style == .card ? -0.2 : 0)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(tint.opacity(0.14), in: Capsule())
                }
            }
        }
    }

    struct Item {
        var text: String
        var state: AgentState
    }

    static func items(for sessions: [AgentSession]) -> [Item] {
        func count(_ state: AgentState) -> Int { sessions.lazy.filter { $0.state == state }.count }
        let counts: [(AgentState, Int, (Int) -> String)] = [
            (.working, count(.working), { "\($0) working" }),
            (.needsPermission, count(.needsPermission), { "\($0) needs you" }),
            (.needsInput, count(.needsInput), { "\($0) waiting" }),
            (.error, count(.error), { "\($0) \($0 == 1 ? "error" : "errors")" }),
        ]
        return counts.filter { $0.1 > 0 }.map { Item(text: $0.2($0.1), state: $0.0) }
    }
}
