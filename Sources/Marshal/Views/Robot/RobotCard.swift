import MarshalCore
import SwiftUI

/// A compact control centre. Only sessions scroll; the timer and health stay visible.
struct RobotCard: View {
    var contentTopInset: CGFloat = 26
    @EnvironmentObject private var state: MarshalState
    @EnvironmentObject private var focus: FocusCoordinator

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("Marshal")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
                QuietControl(style: .card)
                PanelOptions(style: .card)
                Button { state.isRobotExpanded = false } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close Pookie panel")
            }
            .padding(.top, contentTopInset)
            .fixedSize(horizontal: false, vertical: true)

            NudgeBanner(style: .card)
            FocusPanel(style: .card)
                .fixedSize(horizontal: false, vertical: true)
            ActivityDetailsView(style: .card)
            SystemHealthView(style: .card)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.18)))
    }
}

/// A row of colour dots; tap one to change Pookie's skin.
struct SkinPicker: View {
    @EnvironmentObject private var state: MarshalState

    var body: some View {
        HStack(spacing: 6) {
            ForEach(PookieSkin.all) { skin in
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [skin.shellLight, skin.shellDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Circle().strokeBorder(.white.opacity(skin.id == state.skinID ? 0.95 : 0.25), lineWidth: skin.id == state.skinID ? 2 : 1)
                    )
                    .frame(width: 14, height: 14)
                    .scaleEffect(skin.id == state.skinID ? 1.2 : 1)
                    .contentShape(Circle())
                    .onTapGesture { state.skinID = skin.id }
                    .help(skin.name)
            }
        }
        .padding(.top, 4)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: state.skinID)
    }
}

enum Greeting {
    static func text(now: Date = .now) -> String {
        let hour = Calendar.current.component(.hour, from: now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Burning the midnight oil?"
        }
    }
}
