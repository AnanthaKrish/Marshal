import Foundation

/// Turns samples into stable conditions. Pure value type; time is injected.
public struct VitalsAssessor: Sendable {
    /// Conditions after implications (what the face sees).
    public private(set) var conditions: VitalsConditions = []

    // Each own rule's state, before implications.
    private var sweating = false
    private var hot = false
    private var sweatAboveSince: Date?
    private var sweatBelowSince: Date?
    private var hotAboveSince: Date?
    private var hotBelowSince: Date?

    private static let gib: UInt64 = 1 << 30

    public init() {}

    /// Forgets every pending entry and exit, as after sleep: conditions
    /// already held stay held, and each rule re-earns or loses them from
    /// the next samples with its full duration.
    public mutating func resetTimers() {
        sweatAboveSince = nil
        sweatBelowSince = nil
        hotAboveSince = nil
        hotBelowSince = nil
    }

    public mutating func assess(_ v: Vitals, now: Date) -> VitalsConditions {
        // sweating: cpu > 0.60 for 20 s; leave cpu < 0.50 for 10 s
        if sweating {
            sweatAboveSince = nil
            if v.cpu < 0.50 {
                let since = sweatBelowSince ?? now
                sweatBelowSince = since
                if now.timeIntervalSince(since) >= 10 { sweating = false; sweatBelowSince = nil }
            } else {
                sweatBelowSince = nil
            }
        } else {
            sweatBelowSince = nil
            if v.cpu > 0.60 {
                let since = sweatAboveSince ?? now
                sweatAboveSince = since
                if now.timeIntervalSince(since) >= 20 { sweating = true; sweatAboveSince = nil }
            } else {
                sweatAboveSince = nil
            }
        }

        // hot: cpu > 0.85 for 60 s or thermal >= serious; leave cpu < 0.70 for 15 s and thermal < serious
        let seriousThermal = v.thermal >= .serious
        if hot {
            hotAboveSince = nil
            if v.cpu < 0.70 && !seriousThermal {
                let since = hotBelowSince ?? now
                hotBelowSince = since
                if now.timeIntervalSince(since) >= 15 { hot = false; hotBelowSince = nil }
            } else {
                hotBelowSince = nil
            }
        } else {
            hotBelowSince = nil
            if seriousThermal {
                hot = true
                hotAboveSince = nil
            } else if v.cpu > 0.85 {
                let since = hotAboveSince ?? now
                hotAboveSince = since
                if now.timeIntervalSince(since) >= 60 { hot = true; hotAboveSince = nil }
            } else {
                hotAboveSince = nil
            }
        }

        var next = conditions
        func set(_ c: VitalsConditions, _ on: Bool) { if on { next.insert(c) } else { next.remove(c) } }

        set(.sweating, sweating)
        set(.hot, hot)
        set(.overheated, v.thermal == .critical)
        set(.stuffed, v.memoryPressure == .warning)

        // dizzy: pressure critical, or swap > 4 GiB while pressure is at least
        // warning (swap alone is often stale); leave when pressure is below
        // critical and either swap < 3 GiB or pressure is back to normal
        let pressured = v.memoryPressure != .normal
        if v.memoryPressure == .critical || (v.swapUsed > 4 * Self.gib && pressured) {
            next.insert(.dizzy)
        } else if v.memoryPressure != .critical && (v.swapUsed < 3 * Self.gib || !pressured) {
            next.remove(.dizzy)
        }

        if let level = v.batteryLevel {
            if level < 20 && !v.isCharging { next.insert(.sleepy) }
            else if level >= 25 || v.isCharging { next.remove(.sleepy) }
            if level < 10 && !v.isCharging { next.insert(.crying) }
            else if level >= 15 || v.isCharging { next.remove(.crying) }
        } else {
            next.remove([.sleepy, .crying])
        }

        conditions = VitalsConditions.implied(next)
        return conditions
    }
}
