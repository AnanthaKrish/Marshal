import SwiftUI

/// Compact pill button used in both expanded panels.
struct QuickActionButton: View {
    var title: String
    var systemImage: String
    var style: SurfaceStyle
    /// Stretches to the available width. Always on for the card style.
    var fillsWidth = false
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(style.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: style == .card || fillsWidth ? .infinity : nil)
            .background(background, in: Capsule())
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var background: Color {
        switch style {
        case .card: return isHovered ? Color.primary.opacity(0.14) : Color.primary.opacity(0.07)
        case .notch: return isHovered ? Color.white.opacity(0.22) : Color.white.opacity(0.12)
        }
    }

    private var border: Color {
        switch style {
        case .card: return Color.primary.opacity(0.08)
        case .notch: return Color.white.opacity(0.1)
        }
    }
}
