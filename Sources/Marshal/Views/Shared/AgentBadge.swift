import MarshalCore
import SwiftUI

/// A small rounded square tinted per agent, with the agent's glyph.
struct AgentBadge: View {
    var agent: String
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Self.tint(for: agent).gradient)
            .overlay(
                Image(systemName: Self.glyph(for: agent))
                    .font(.system(size: size * 0.48, weight: .bold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    static func glyph(for agent: String) -> String {
        switch agent {
        case HookAgent.claudeCode.rawValue: "terminal"
        case HookAgent.codex.rawValue: "chevron.left.forwardslash.chevron.right"
        case HookAgent.cursor.rawValue: "cursorarrow"
        default: "circle.dotted"
        }
    }

    static func tint(for agent: String) -> Color {
        switch agent {
        case HookAgent.claudeCode.rawValue: Color(red: 0.85, green: 0.47, blue: 0.30)   // warm orange
        case HookAgent.codex.rawValue: Color(red: 0.10, green: 0.62, blue: 0.54)        // teal
        case HookAgent.cursor.rawValue: Color(red: 0.51, green: 0.58, blue: 0.95)
        default: Color(white: 0.55)
        }
    }
}
