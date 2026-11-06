import SwiftUI

/// A single-colour outline, always attached to the shell. Only this overlay animates.
struct CompletionRim: View {
    var style: CompletionLightStyle
    var color: Color
    var outline: RoundedRectangle
    var lineWidth: CGFloat
    var animates: Bool
    var replay: Int
    var frameTime: Double?
    @State private var startedAt = Date.now

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animates || !style.animates)) { context in
            let elapsed = frameTime ?? context.date.timeIntervalSince(startedAt)
            let sample = style.sample(at: elapsed, reduceMotion: !animates && frameTime == nil)
            let border = outline.inset(by: lineWidth / 2)
            ZStack {
                border.stroke(color.opacity(sample.opacity), lineWidth: lineWidth * 0.8)
                    .shadow(color: color.opacity(sample.opacity * 0.25), radius: lineWidth)
                if let progress = sample.trace {
                    border.trim(from: max(0, progress - 0.22), to: progress)
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .opacity(sample.traceOpacity)
                }
            }
        }
        .onChange(of: replay) { _, _ in startedAt = .now }
        .onChange(of: style) { _, _ in startedAt = .now }
        .onAppear { startedAt = .now }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
