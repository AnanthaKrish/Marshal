import AppKit
import Combine

/// Drives the robot's personality: blinking and eyes that follow the cursor.
/// `anchor` must return the robot's eye position in screen coordinates.
/// While `isScanning` (an agent is working) the eyes sweep side to side
/// instead of following the cursor.
@MainActor
final class RobotBrain: ObservableObject {
    /// Normalised gaze direction, each axis in -1...1.
    @Published private(set) var gaze: CGPoint = .zero
    @Published private(set) var isBlinking = false
    var isScanning = false
    /// Multiplies how long the eyes stay closed per blink (3 when sleepy).
    var blinkScale: Double = 1

    private var gazeTask: Task<Void, Never>?
    private var blinkTask: Task<Void, Never>?
    private var anchor: (() -> CGPoint)?

    func start(anchor: @escaping () -> CGPoint) {
        self.anchor = anchor
        guard gazeTask == nil else { return }

        gazeTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.updateGaze()
                try? await Task.sleep(for: .milliseconds(33))
            }
        }

        blinkTask = Task { [weak self] in
            while !Task.isCancelled {
                let pause = Double.random(in: 2.5...6)
                try? await Task.sleep(for: .seconds(pause))
                guard !Task.isCancelled else { break }
                self?.isBlinking = true
                let scale = self?.blinkScale ?? 1
                try? await Task.sleep(for: .milliseconds(130 * scale))
                self?.isBlinking = false
                // Occasionally double-blink.
                if Bool.random() && Int.random(in: 0..<3) == 0 {
                    try? await Task.sleep(for: .milliseconds(160 * scale))
                    self?.isBlinking = true
                    try? await Task.sleep(for: .milliseconds(120 * scale))
                    self?.isBlinking = false
                }
            }
        }
    }

    func stop() {
        gazeTask?.cancel()
        blinkTask?.cancel()
        gazeTask = nil
        blinkTask = nil
    }

    /// The side-to-side sweep used while an agent is working, -0.8...0.8.
    /// Shared with the notch eyes so both widgets scan in step.
    static func scanX(at date: Date) -> CGFloat {
        0.8 * sin(date.timeIntervalSinceReferenceDate * 1.2)
    }

    /// Inside this distance the cursor always wins over scanning, so Pookie
    /// looks at you whenever you come close.
    static let attentionRadius: CGFloat = 220

    private func updateGaze() {
        guard let anchor else { return }
        let eye = anchor()
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - eye.x
        let dy = mouse.y - eye.y
        let cursorIsNear = hypot(dx, dy) < Self.attentionRadius

        let next: CGPoint
        if isScanning && !cursorIsNear {
            next = CGPoint(x: Self.scanX(at: .now), y: 0)
        } else {
            // Full deflection once the cursor is ~160pt away.
            let reach: CGFloat = 160
            next = CGPoint(
                x: max(-1, min(1, dx / reach)),
                y: max(-1, min(1, dy / reach))
            )
        }
        // Light smoothing so the eyes glide instead of jitter.
        gaze = CGPoint(
            x: gaze.x + (next.x - gaze.x) * 0.25,
            y: gaze.y + (next.y - gaze.y) * 0.25
        )
    }
}
