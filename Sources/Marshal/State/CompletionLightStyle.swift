import Foundation

/// Only the rim shown when a chat/focus session finishes. Never changes the face or body.
enum CompletionLightStyle: String, CaseIterable, Identifiable, Sendable {
    case steady, breathe, trace, off
    var id: String { rawValue }
    static let `default`: Self = .trace
    static let previewDuration = 4.8
    static let cycleDuration = 4.0

    var name: String {
        switch self {
        case .steady: "Steady glow"
        case .breathe: "Soft breath"
        case .trace: "Light trace"
        case .off: "Off"
        }
    }
    var detail: String {
        switch self {
        case .steady: "A quiet, constant green outline."
        case .breathe: "Gently brightens and dims. No flashing."
        case .trace: "One smooth lap, then a steady glow."
        case .off: "No completion rim light."
        }
    }
    var symbol: String {
        switch self {
        case .steady: "square"
        case .breathe: "sun.max"
        case .trace: "arrow.clockwise"
        case .off: "slash.circle"
        }
    }
    var animates: Bool { self == .breathe || self == .trace }

    func sample(at elapsed: Double, reduceMotion: Bool = false) -> CompletionLightSample {
        if self == .off { return CompletionLightSample(opacity: 0) }
        guard !reduceMotion, elapsed.isFinite, elapsed >= 0 else { return .steady }
        switch self {
        case .steady, .off: return .steady
        case .breathe:
            let phase = elapsed.truncatingRemainder(dividingBy: Self.cycleDuration) / Self.cycleDuration
            return CompletionLightSample(opacity: 0.45 + 0.30 * (1 - cos(phase * 2 * .pi)) / 2)
        case .trace:
            guard elapsed < Self.cycleDuration else { return .steady }
            let progress = elapsed / Self.cycleDuration
            return CompletionLightSample(opacity: 0.35 + 0.30 * progress,
                                         trace: progress, traceOpacity: sin(.pi * progress))
        }
    }
}

struct CompletionLightSample: Equatable {
    var opacity: Double
    var trace: Double? = nil
    var traceOpacity = 0.0
    static let steady = Self(opacity: 0.65)
}
