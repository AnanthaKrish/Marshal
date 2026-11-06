import SwiftUI

/// A continuous outline with a small travelling light, or a gentle attention
/// pulse. The open top lets the island keep merging into the physical notch.
struct NotchBorder: View {
    var light: ActivityLight
    var flare: CGFloat
    var bottomRadius: CGFloat
    var expanded: Bool
    var hovered: Bool
    var animates: Bool

    private var moving: Bool { animates && light.period > 0 }
    private var lineWidth: CGFloat { expanded ? 1.25 : 1.5 }
    private var outline: NotchShape {
        NotchShape(flare: flare, bottomRadius: bottomRadius, closesTop: false)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { context in
            // A fixed phase makes paused, quiet, reduced-motion and snapshot
            // renders steady even when other state refreshes the view.
            let phase = moving
                ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: light.period) / light.period
                : 0.42
            rim(phase: phase)
        }
        .animation(animates ? .easeInOut(duration: 0.4) : nil, value: light.color)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func rim(phase: Double) -> some View {
        let color = light.color
        let breathing = moving && light.pulses ? 0.5 - 0.5 * cos(phase * 2 * .pi) : 0.5
        let opacity = light.isQuiet ? 0.22 : (hovered ? 0.65 : 0.42) + (light.pulses ? breathing * 0.3 : 0)
        return ZStack {
            // Halo lives outside the content clip, inside the window's shadow margin.
            outline.stroke(color.opacity(opacity * 0.6), lineWidth: lineWidth * 2.5)
                .blur(radius: expanded ? 4 : 2.5)
            outline.stroke(color.opacity(opacity), lineWidth: lineWidth)

            if let progress = light.progress {
                outline.trim(from: 0, to: min(1, max(0, progress)))
                    .stroke(color.opacity(light.isQuiet ? 0.3 : 0.9), style: StrokeStyle(lineWidth: lineWidth + 0.35, lineCap: .round))
                    .shadow(color: color.opacity(0.5), radius: 3)
                    .animation(moving ? .linear(duration: 1) : nil, value: progress)
            }

            if !light.pulses && !light.isQuiet {
                // Wrap the highlight across the two open ends, above the screen.
                let length = 0.18
                highlight(from: phase, to: min(1, phase + length))
                if phase + length > 1 {
                    highlight(from: 0, to: phase + length - 1)
                }
            }
        }
    }

    private func highlight(from start: Double, to end: Double) -> some View {
        outline.trim(from: start, to: end)
            .stroke(
                LinearGradient(colors: [light.color.opacity(0.4), light.color, light.color.opacity(0.4)],
                               startPoint: .leading, endPoint: .trailing),
                style: StrokeStyle(lineWidth: lineWidth + 0.5, lineCap: .round)
            )
            .shadow(color: light.color.opacity(0.65), radius: 3)
    }
}
