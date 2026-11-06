import MarshalCore
import SwiftUI

/// The whole of Pookie: the floating head with a rim light that travels
/// around its edge, and a floor shadow. Everything is proportional to
/// `size`, the head width.
struct PookieFigure: View {
    var size: CGFloat
    var skin: PookieSkin
    var gaze: CGPoint = .zero
    var isBlinking = false
    var isHappy = false
    var isHovered = false
    var mood: AgentState? = nil
    var isCelebrating = false
    var completionLightStyle: CompletionLightStyle = .default
    var lightReplay = 0
    /// A fixed rim-light time for snapshot renders.
    var lightFrame: Double? = nil
    /// What the machine's vitals add to the figure.
    var vitals: VitalsLook = .none
    var focusProgress: Double? = nil
    var isQuiet = false
    var isYawning = false
    var showsFloorShadow = true
    var activity: ActivitySignal? = nil
    /// Set false for static renders so nothing animates.
    var animates = true

    // Vertical budget, as multiples of `size`.
    static let antennaHeight: CGFloat = 0.0
    static let shadowHeight: CGFloat = 0.16
    static let widthFactor: CGFloat = 1.12

    static func frameSize(for size: CGFloat) -> CGSize {
        let height = size * (antennaHeight + shadowHeight) + RobotFace.height(for: size)
        return CGSize(width: size * widthFactor, height: height)
    }

    /// Distance from the top of the figure to where a card may start so the
    /// head overlaps its top edge.
    static func shoulderOffset(for size: CGFloat) -> CGFloat {
        size * antennaHeight + RobotFace.height(for: size) * 0.72
    }

    var body: some View {
        VStack(spacing: 0) {
            RobotFace(
                size: size, skin: skin, gaze: gaze, isBlinking: isBlinking,
                isHappy: isHappy, isHovered: isHovered, mood: mood, isCelebrating: isCelebrating,
                vitals: vitals, isYawning: isYawning, animates: animates,
                rimLight: rimLight, completionLightStyle: completionLightStyle,
                lightReplay: lightReplay, lightFrame: lightFrame
            )
            .modifier(Wobble(active: animates && vitals.wobble))

            floorShadow
                .opacity(showsFloorShadow ? 1 : 0)
                .frame(height: size * Self.shadowHeight, alignment: .bottom)
        }
        .frame(width: Self.frameSize(for: size).width, height: Self.frameSize(for: size).height)
    }

    // MARK: Mood → rim light

    private var rimLight: ActivityLight {
        ActivityLight(signal: activity ?? previewActivity, skin: skin, heat: vitals.heat)
    }

    /// Standalone mood renders have no coordinator; live widgets always supply activity.
    private var previewActivity: ActivitySignal {
        if isQuiet { return .quiet(focusProgress: focusProgress) }
        if mood == .error { return .error }
        if mood == .needsPermission { return .permission }
        if let focusProgress { return .focus(progress: focusProgress, paused: false) }
        if isCelebrating { return .finished }
        if isYawning { return .reminder }
        switch mood {
        case .needsInput: return .waiting
        case .working: return .working
        default: return .idle
        }
    }

    // MARK: Parts

    private var floorShadow: some View {
        Ellipse()
            .fill(.black.opacity(0.22))
            .frame(width: size * 0.66, height: size * 0.09)
            .blur(radius: 3)
    }
}

// MARK: - Rim light

/// A bright arc that travels around the head's edge. Each mood sets its
/// colour, speed and whether it pulses: a slow, soft sweep when idle; a quick
/// green sweep while agents work; a fast amber pulse when one needs you; a
/// settled green outline on finish; a gentle red pulse on errors.
struct RimLight: View {
    var light: ActivityLight
    var outline: RoundedRectangle
    var lineWidth: CGFloat
    var boost: Bool
    /// Halves the idle sweep (sleepy).
    var dim: Bool = false
    var animates: Bool
    var completionStyle: CompletionLightStyle = .default
    var replay = 0
    var frameTime: Double? = nil

    private var color: Color { light.color }
    private var period: Double { light.period }
    private var pulses: Bool { light.pulses }

    private var baseOpacity: Double {
        if light.isQuiet { return 0.3 }
        if light.signal == .idle { return (boost ? 0.9 : 0.55) * (dim ? 0.5 : 1) }
        return 0.95
    }

    private var stops: [Color] { [.clear, .clear, color, .clear, .clear] }

    var body: some View {
        if light.signal == .finished {
            CompletionRim(style: completionStyle, color: color, outline: outline,
                          lineWidth: lineWidth, animates: animates, replay: replay, frameTime: frameTime)
        } else if let progress = light.progress {
            let shape = outline.inset(by: lineWidth / 2)
            ZStack {
                shape.stroke(color.opacity(0.22), lineWidth: lineWidth)
                shape.trim(from: 0, to: max(0.015, progress))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .shadow(color: color.opacity(0.7), radius: 3)
            }
            .opacity(light.isQuiet ? 0.3 : 1)
            .allowsHitTesting(false)
        } else if animates, period > 0 {
            TimelineView(.animation(minimumInterval: 1.0 / 40)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                arc(angle: t.truncatingRemainder(dividingBy: period) / period * 360)
            }
            .modifier(Pulse(active: pulses, period: period / 2))
        } else {
            arc(angle: 300)
        }
    }

    private func arc(angle: Double) -> some View {
        let gradient = AngularGradient(colors: stops, center: .center, angle: .degrees(angle))
        return ZStack {
            // A tight glow on the shell bevel, rather than a detached halo.
            outline
                .strokeBorder(gradient, lineWidth: lineWidth)
                .blur(radius: lineWidth * 0.4)
                .opacity(0.25)
            // Crisp arc
            outline
                .strokeBorder(gradient, lineWidth: lineWidth)
        }
        .opacity(baseOpacity)
        .allowsHitTesting(false)
    }
}

/// Fades a view in and out while active; the animator exists only then.
private struct Pulse: ViewModifier {
    var active: Bool
    var period: Double

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 1.0, repeating: active) { view, opacity in
            view.opacity(active ? opacity : 1)
        } keyframes: { _ in
            LinearKeyframe(0.25, duration: period)
            LinearKeyframe(1.0, duration: period)
        }
    }
}

/// Rocks the head ±3° on a slow 3 s ease loop while dizzy. The rotation is
/// always applied (0° when inactive) so toggling never swaps the face's
/// view identity: the tear and spiral timelines keep running, and the head
/// eases in from 0° and back to it rather than snapping.
private struct Wobble: ViewModifier {
    var active: Bool

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 0.0, repeating: active) { view, degrees in
                view.rotationEffect(.degrees(degrees))
            } keyframes: { _ in
                // From the centre out to the left, across to the right and
                // back to the centre, so each loop starts where the last ended.
                LinearKeyframe(-3.0, duration: 0.75, timingCurve: .easeOut)
                LinearKeyframe(3.0, duration: 1.5, timingCurve: .easeInOut)
                LinearKeyframe(0.0, duration: 0.75, timingCurve: .easeIn)
            }
            .animation(.easeOut(duration: 0.3), value: active)
    }
}
