import AppKit
import MarshalCore
import SwiftUI

/// Pookie's head: a rounded shell, a dark face screen, glowing eyes that look
/// around, and a mouth that smiles when it's happy. Everything is
/// proportional to `size` (the head width). The antenna and body live in
/// `PookieFigure`.
struct RobotFace: View {
    var size: CGFloat
    var skin: PookieSkin
    var gaze: CGPoint
    var isBlinking: Bool
    var isHappy: Bool
    var isHovered: Bool
    var mood: AgentState? = nil
    var isCelebrating: Bool = false
    /// What the machine's vitals add to the face.
    var vitals: VitalsLook = .none
    var isYawning = false
    /// Set false for static renders so nothing animates.
    var animates: Bool = true
    var rimLight: ActivityLight? = nil
    var completionLightStyle: CompletionLightStyle = .default
    var lightReplay = 0
    var lightFrame: Double? = nil

    private var isCrying: Bool { mood == .error && !isCelebrating }
    /// Crying for either reason: an agent error (red) or a low battery (blue).
    private var isSad: Bool { isCrying || (vitals.coldTears && !isCelebrating) }

    private var shellLight: Color { skin.shellLight.blended(toward: RobotPalette.heat, by: vitals.heat) }
    private var shellDark: Color { skin.shellDark.blended(toward: RobotPalette.heat, by: vitals.heat) }
    private var shellOutline: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
    }

    static func height(for size: CGFloat) -> CGFloat { size * 0.86 }

    var body: some View {
        ZStack {
            // Ears
            HStack {
                ear
                Spacer()
                ear
            }
            .frame(width: size + size * 0.12)

            // Shell
            shellOutline
                .fill(
                    LinearGradient(
                        colors: [shellLight, shellDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    shellOutline
                        .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                )
                .overlay(alignment: .top) {
                    shellOutline
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.35), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
                .shadow(color: shellDark.opacity(0.35), radius: 6, y: 4)
                .overlay {
                    if let rimLight {
                        // The shell can outgrow the face's layout frame because of the ears.
                        // Draw on the shell itself, with its exact path and bounds.
                        RimLight(light: rimLight, outline: shellOutline, lineWidth: size * 0.028,
                                 boost: isHovered, dim: vitals.rimDim, animates: animates,
                                 completionStyle: completionLightStyle, replay: lightReplay, frameTime: lightFrame)
                            .clipShape(shellOutline)
                    }
                }

            // Face screen
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(skin.screen)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, size * 0.07)
                .padding(.top, size * 0.11)
                .padding(.bottom, size * 0.10)

            // Eyes + mouth
            VStack(spacing: size * 0.07) {
                HStack(spacing: size * 0.14) {
                    eye
                    eye
                }
                mouth
            }
            .offset(x: gaze.x * size * 0.035, y: -gaze.y * size * 0.03)

            // Tears when an agent has failed (skin colour), or when the
            // battery is nearly flat (ice blue). The agent's tears win.
            if isSad {
                let color = isCrying ? skin.eye : RobotPalette.coldTear
                HStack(spacing: size * 0.22) {
                    Tear(size: size, color: color, delay: 0.0, animates: animates)
                    Tear(size: size, color: color, delay: 0.45, animates: animates)
                }
                .offset(x: gaze.x * size * 0.03, y: size * 0.02)
                .transition(.opacity)
            }

            // Blush when happy; puffed cheeks when memory is stuffed.
            if isCelebrating || isHappy || vitals.puffCheeks {
                HStack {
                    cheek
                    Spacer()
                    cheek
                }
                .padding(.horizontal, size * (vitals.puffCheeks ? 0.12 : 0.16))
                .offset(y: size * 0.1)
                .transition(.opacity)
            }

            // Sweat on the temples: the right one first, both when hot.
            if vitals.sweat > 0 {
                Sweat(size: size, color: skin.eye, count: vitals.sweat, animates: animates)
                    .offset(y: -Self.height(for: size) / 2 + size * 0.18)
            }
        }
        .frame(width: size, height: Self.height(for: size))
        .animation(.easeOut(duration: 0.2), value: isCelebrating || isHappy)
        .animation(.easeOut(duration: 0.3), value: vitals)
    }

    // MARK: Parts

    private var ear: some View {
        RoundedRectangle(cornerRadius: size * 0.04, style: .continuous)
            .fill(skin.metal)
            .frame(width: size * 0.08, height: size * 0.24)
    }

    private var eye: some View {
        Group {
            if isCelebrating {
                // Heart eyes.
                Image(systemName: "heart.fill")
                    .font(.system(size: size * 0.19, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [RobotPalette.blush.opacity(0.95), RobotPalette.blush],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .overlay(alignment: .topLeading) {
                        Circle()
                            .fill(.white.opacity(0.85))
                            .frame(width: size * 0.035, height: size * 0.035)
                            .offset(x: size * 0.035, y: size * 0.03)
                    }
                    .shadow(color: RobotPalette.blush.opacity(0.8), radius: 4)
                    .frame(width: size * 0.2, height: size * 0.21)
            } else {
                let open = isSad ? size * 0.15 : size * 0.21
                let eyeHeight = isBlinking ? size * 0.03 : (vitals.squint ? open * 0.45 : open)
                ZStack {
                    Capsule()
                        .fill(skin.eye)
                    if !isBlinking {
                        if vitals.spiralEyes {
                            SpiralPupil(size: size, color: skin.screen, animates: animates)
                        } else {
                            pupil
                        }
                    }
                    if vitals.sleepyLids && !isBlinking {
                        // A shell-coloured lid over the top 40% of the eye.
                        VStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: size * 0.02, style: .continuous)
                                .fill(shellDark)
                                .frame(height: eyeHeight * 0.4)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(width: size * 0.15, height: eyeHeight)
                .clipShape(Capsule())
            }
        }
        .shadow(color: skin.eye.opacity(0.8), radius: isHovered ? 7 : 4)
        .offset(x: gaze.x * size * 0.03, y: -gaze.y * size * 0.03)
        .animation(.easeOut(duration: 0.08), value: isBlinking)
    }

    /// A dark pupil that drifts a little further than the eye with the gaze,
    /// with a catchlight in its upper corner.
    private var pupil: some View {
        ZStack {
            Circle()
                .fill(skin.screen.opacity(0.92))
                .frame(width: size * 0.075, height: size * 0.075)
            Circle()
                .fill(.white.opacity(0.9))
                .frame(width: size * 0.025, height: size * 0.025)
                .offset(x: -size * 0.016, y: -size * 0.018)
        }
        .offset(x: gaze.x * size * 0.03, y: -gaze.y * size * 0.045 + (isSad ? size * 0.02 : 0))
    }

    private var mouth: some View {
        Group {
            if isCelebrating {
                SmileShape()
                    .stroke(skin.eye, style: StrokeStyle(lineWidth: size * 0.035, lineCap: .round))
                    .frame(width: size * 0.22, height: size * 0.09)
            } else if isYawning {
                Ellipse().fill(skin.eye.opacity(0.9))
                    .frame(width: size * 0.10, height: size * 0.12)
            } else if vitals.pant {
                PantMouth(size: size, color: skin.eye, animates: animates)
            } else if isHappy {
                SmileShape()
                    .stroke(skin.eye, style: StrokeStyle(lineWidth: size * 0.035, lineCap: .round))
                    .frame(width: size * 0.22, height: size * 0.09)
            } else if isSad {
                // A frown: the smile upside down.
                SmileShape()
                    .stroke(skin.eye, style: StrokeStyle(lineWidth: size * 0.035, lineCap: .round))
                    .frame(width: size * 0.18, height: size * 0.07)
                    .rotationEffect(.degrees(180))
                    .offset(y: size * 0.02)
            } else {
                Capsule()
                    .fill(skin.eye.opacity(0.9))
                    .frame(width: size * 0.14, height: size * 0.035)
            }
        }
        .shadow(color: skin.eye.opacity(0.6), radius: 3)
        .frame(height: size * 0.09)
    }

    private var cheek: some View {
        let scale: CGFloat = vitals.puffCheeks ? 1.6 : 1
        return Ellipse()
            .fill(vitals.puffCheeks ? skin.bodyLight.opacity(0.7) : RobotPalette.blush.opacity(0.55))
            .frame(width: size * 0.11 * scale, height: size * 0.06 * scale)
            .blur(radius: 1.5)
    }
}

/// Sweat drops that slide down from the temples and fade, every 2.4 s: the
/// right temple first, the left too when `count` is 2. One timeline drives
/// both; the second drop runs half a loop behind so they don't fall in step.
private struct Sweat: View {
    var size: CGFloat
    var color: Color
    var count: Int
    var animates: Bool

    static let period = 2.4
    /// The left drop's lag behind the right one, in seconds.
    static let lag = 1.2

    var body: some View {
        if animates {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                drops(at: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            drops(at: nil)
        }
    }

    /// Both drops at their temples, at time `t` (nil: a still frame).
    private func drops(at t: Double?) -> some View {
        ZStack {
            ForEach(0..<min(count, 2), id: \.self) { index in
                let m = motion(index: index, at: t)
                drop
                    .offset(x: index == 0 ? size * 0.42 : -size * 0.42, y: m.y)
                    .opacity(m.opacity)
            }
        }
    }

    /// How far drop `index` has fallen and how visible it is at `t`.
    private func motion(index: Int, at t: Double?) -> (y: CGFloat, opacity: Double) {
        guard let t else { return (size * 0.08, 1) }
        let phase = (t + Double(index) * Self.lag).truncatingRemainder(dividingBy: Self.period) / Self.period
        let opacity = phase < 0.15 ? phase / 0.15 : (phase > 0.7 ? (1 - phase) / 0.3 : 1)
        return (phase * size * 0.22, opacity)
    }

    private var drop: some View {
        TeardropShape()
            .fill(
                LinearGradient(colors: [.white.opacity(0.9), color], startPoint: .top, endPoint: .bottom)
            )
            .frame(width: size * 0.05, height: size * 0.08)
            .shadow(color: color.opacity(0.7), radius: 1.5)
            .allowsHitTesting(false)
    }
}

/// The overheated mouth: a small open oval that pants.
private struct PantMouth: View {
    var size: CGFloat
    var color: Color
    var animates: Bool

    var body: some View {
        if animates {
            oval.phaseAnimator([1.0, 1.25]) { content, scale in
                content.scaleEffect(scale)
            } animation: { _ in .easeInOut(duration: 0.4) }
        } else {
            oval
        }
    }

    private var oval: some View {
        Ellipse()
            .fill(color.opacity(0.9))
            .frame(width: size * 0.12, height: size * 0.07)
    }
}

/// A dizzy pupil: a small spiral that turns once every 4 s.
private struct SpiralPupil: View {
    var size: CGFloat
    var color: Color
    var animates: Bool

    static let period = 4.0

    var body: some View {
        if animates {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                spiral.rotationEffect(.degrees(t.truncatingRemainder(dividingBy: Self.period) / Self.period * 360))
            }
        } else {
            spiral
        }
    }

    private var spiral: some View {
        SpiralShape(turns: 2.5)
            .stroke(color, style: StrokeStyle(lineWidth: size * 0.018, lineCap: .round))
            .frame(width: size * 0.11, height: size * 0.11)
    }
}

/// An Archimedean spiral from the centre out to the edge of `rect`.
struct SpiralShape: Shape {
    var turns: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maxRadius = min(rect.width, rect.height) / 2
        let steps = max(Int(turns * 48), 2)
        for i in 0...steps {
            let f = Double(i) / Double(steps)
            let angle = f * turns * 2 * .pi
            let r = maxRadius * f
            let point = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

extension Color {
    /// This colour mixed toward `other` by `amount` (0 = self, 1 = other), in sRGB.
    func blended(toward other: Color, by amount: Double) -> Color {
        guard amount > 0 else { return self }
        guard let a = NSColor(self).usingColorSpace(.sRGB),
              let b = NSColor(other).usingColorSpace(.sRGB) else { return self }
        let t = CGFloat(min(amount, 1))
        func mix(_ x: CGFloat, _ y: CGFloat) -> Double { Double(x + (y - x) * t) }
        return Color(.sRGB,
                     red: mix(a.redComponent, b.redComponent),
                     green: mix(a.greenComponent, b.greenComponent),
                     blue: mix(a.blueComponent, b.blueComponent),
                     opacity: mix(a.alphaComponent, b.alphaComponent))
    }
}

/// One teardrop that falls from an eye, fades, and starts again.
private struct Tear: View {
    var size: CGFloat
    var color: Color
    var delay: Double
    var animates: Bool

    var body: some View {
        if animates {
            drop.phaseAnimator([0.0, 1.0]) { content, phase in
                content
                    .offset(y: phase * size * 0.26)
                    .opacity(phase < 0.15 ? phase / 0.15 : 1 - (phase - 0.15) / 0.85)
            } animation: { _ in .easeIn(duration: 1.1).delay(delay) }
        } else {
            drop.offset(y: size * 0.08)
        }
    }

    private var drop: some View {
        TeardropShape()
            .fill(
                LinearGradient(colors: [.white.opacity(0.9), color], startPoint: .top, endPoint: .bottom)
            )
            .frame(width: size * 0.06, height: size * 0.09)
            .shadow(color: color.opacity(0.7), radius: 2)
    }
}

/// A classic teardrop: pointed at the top, round at the bottom.
struct TeardropShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.maxY - r)
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: center.y), control: CGPoint(x: rect.maxX, y: rect.minY + r))
        path.addArc(center: center, radius: r, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY + r))
        path.closeSubpath()
        return path
    }
}

/// A gentle upward-curving smile.
struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.6)
        )
        return path
    }
}

/// Colours that mean the same thing on every skin.
enum RobotPalette {
    /// Antenna and notch label when an agent is waiting on you.
    static let attention = Color(red: 1.0, green: 0.64, blue: 0.08)
    /// Antenna and notch label when an agent has failed.
    static let alert = Color(red: 1.0, green: 0.33, blue: 0.33)
    /// Beacon while agents are working.
    static let working = Color(red: 0.18, green: 0.85, blue: 0.42)
    /// Beacon right after an agent finishes.
    static let done = Color(red: 0.35, green: 0.95, blue: 0.45)
    /// Cheeks.
    static let blush = Color(red: 1.0, green: 0.45, blue: 0.55)
    /// Thruster flame.
    static let flame = Color(red: 1.0, green: 0.70, blue: 0.30)
    /// What the shell blushes toward when the machine runs hot.
    static let heat = Color(red: 1.0, green: 0.42, blue: 0.25)
    /// Tears when the battery is nearly flat.
    static let coldTear = Color(red: 0.55, green: 0.80, blue: 1.0)
}
