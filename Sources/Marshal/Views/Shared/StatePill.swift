import MarshalCore
import SwiftUI

/// A tinted capsule naming a session's state.
struct StatePill: View {
    var state: AgentState
    var style: SurfaceStyle

    var body: some View {
        let tint = Self.tint(for: state, style: style)
        Text(Self.label(for: state))
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            // Bright tints wash out on the light card; darken the text there only.
            .brightness(style == .card ? -0.2 : 0)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.16), in: Capsule())
    }

    static func label(for state: AgentState) -> String {
        switch state {
        case .working: "Working"
        case .needsPermission: "Needs permission"
        case .needsInput: "Waiting for you"
        case .done: "Finished"
        case .error: "Error"
        case .idle, .ended: "Idle"
        }
    }

    /// Amber when the agent waits on you, red for errors, green while working,
    /// grey once finished or idle. Also used for the compact chip's dot.
    static func tint(for state: AgentState, style: SurfaceStyle) -> Color {
        switch state {
        case .needsPermission, .needsInput: RobotPalette.attention
        case .error: RobotPalette.alert
        case .working: RobotPalette.working
        case .done, .idle, .ended: style.secondary
        }
    }
}
