import Foundation

/// A deadline rather than a decrementing counter: late ticks and sleep do not drift.
public struct FocusTimer: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable { case idle, running, paused, completed }
    public private(set) var phase: Phase = .idle
    public private(set) var duration: TimeInterval = 25 * 60
    public private(set) var deadline: Date?
    public private(set) var pausedRemaining: TimeInterval = 0
    public private(set) var completedAt: Date?

    public init() {}

    public func remaining(at now: Date) -> TimeInterval {
        switch phase {
        case .idle: duration
        case .running: min(duration, max(0, deadline?.timeIntervalSince(now) ?? 0))
        case .paused: pausedRemaining
        case .completed: 0
        }
    }

    public func progress(at now: Date) -> Double {
        phase == .idle ? 0 : min(1, max(0, 1 - remaining(at: now) / duration))
    }

    public mutating func start(minutes: Int, now: Date) {
        duration = TimeInterval(min(180, max(1, minutes)) * 60)
        deadline = now.addingTimeInterval(duration)
        pausedRemaining = 0
        completedAt = nil
        phase = .running
    }

    public mutating func pause(now: Date) {
        advance(now: now)
        guard phase == .running else { return }
        pausedRemaining = remaining(at: now)
        deadline = nil
        phase = .paused
    }

    public mutating func resume(now: Date) {
        guard phase == .paused else { return }
        deadline = now.addingTimeInterval(pausedRemaining)
        pausedRemaining = 0
        phase = .running
    }

    public mutating func advance(now: Date) {
        guard phase == .running, let deadline, now >= deadline else { return }
        completedAt = deadline
        self.deadline = nil
        phase = .completed
    }

    public mutating func reset() { self = FocusTimer() }

    /// Reject corrupt persisted timers instead of letting them produce invalid UI values.
    public var isValid: Bool {
        guard duration.isFinite, (60...10_800).contains(duration),
              pausedRemaining.isFinite, (0...duration).contains(pausedRemaining) else { return false }
        switch phase {
        case .idle: return deadline == nil && completedAt == nil
        case .running: return deadline?.timeIntervalSince1970.isFinite == true && completedAt == nil
        case .paused: return pausedRemaining > 0 && deadline == nil && completedAt == nil
        case .completed: return completedAt?.timeIntervalSince1970.isFinite == true && deadline == nil
        }
    }

    public static func clockText(_ seconds: TimeInterval) -> String {
        let value = Int(ceil(max(0, seconds)))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
