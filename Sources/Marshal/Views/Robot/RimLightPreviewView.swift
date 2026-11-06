import SwiftUI

struct RimLightPreviewView: View {
    @ObservedObject var state: MarshalState
    @ObservedObject var preview: RimLightPreviewModel
    var close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("Pookie's rim light")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                Text("Choose the light shown when a chat finishes.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }

            VStack(spacing: 5) {
                PookieFigure(size: 108, skin: state.skin,
                             completionLightStyle: preview.selected, lightReplay: preview.trigger,
                             activity: .finished,
                             animates: preview.isPlaying && !reduceMotion && !isSnapshot)
                    .frame(height: 115)
                    .accessibilityLabel("Rim light preview: \(preview.selected.name)")
                Text(preview.isPlaying ? "Playing · \(preview.selected.name)" : "Preview only · no chats needed")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(state.skin.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))

            VStack(spacing: 7) {
                ForEach(CompletionLightStyle.allCases) { style in
                    Button { preview.play(style) } label: {
                        HStack(spacing: 11) {
                            Image(systemName: style.symbol)
                                .font(.system(size: 17, weight: .medium))
                                .frame(width: 25)
                                .foregroundStyle(preview.selected == style ? state.skin.accent : .secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(style.name).font(.system(size: 12, weight: .semibold))
                                    if state.completionLightStyle == style {
                                        Text("Current").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                                    }
                                }
                                Text(style.detail).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: preview.selected == style ? "play.circle.fill" : "play.circle")
                                .foregroundStyle(preview.selected == style ? state.skin.accent : .secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .contentShape(RoundedRectangle(cornerRadius: 11))
                        .background(preview.selected == style ? state.skin.accent.opacity(0.09) : Color.primary.opacity(0.025),
                                    in: RoundedRectangle(cornerRadius: 11))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11)
                                .strokeBorder(preview.selected == style ? state.skin.accent.opacity(0.5) : .clear, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Preview \(style.name). \(style.detail)")
                }
            }

            HStack(spacing: 8) {
                Button { preview.play() } label: { Label("Replay", systemImage: "arrow.clockwise") }
                Button(preview.isTryingAll ? "Stop" : "Try all") {
                    if preview.isTryingAll { preview.stop() } else { preview.tryAll() }
                }
                Spacer()
                Button {
                    state.completionLightStyle = preview.selected
                    preview.stop()
                    close()
                } label: {
                    Text("Use this").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.85))
                        .padding(.horizontal, 13).padding(.vertical, 7)
                        .background(state.skin.accent, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
            Text(reduceMotion ? "Reduce Motion is on · lights stay steady." : "Light only · no chats needed. “Use this” saves it.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 360)
        .background(.background)
        .onAppear { if !isSnapshot { preview.play() } }
        .onDisappear { preview.stop() }
    }
}
