import Testing
import Foundation
@testable import MarshalCore

struct VitalsAssessorTests {
    static let t0 = Date(timeIntervalSince1970: 1_000_000)
    static let gib: UInt64 = 1 << 30

    func at(_ s: Double) -> Date { Self.t0.addingTimeInterval(s) }

    /// Feeds `v` every second from `from` through `to` inclusive; returns the last result.
    @discardableResult
    func feed(_ a: inout VitalsAssessor, _ v: Vitals, from: Double, to: Double) -> VitalsConditions {
        var r: VitalsConditions = []
        var t = from
        while t <= to { r = a.assess(v, now: at(t)); t += 1 }
        return r
    }

    @Test func sweatingEntersAfterTwentySecondsAbove60() {
        var a = VitalsAssessor()
        let v = Vitals(cpu: 0.61)
        #expect(!feed(&a, v, from: 0, to: 19).contains(.sweating))
        #expect(a.assess(v, now: at(20)).contains(.sweating))
        // a dip resets the window
        var b = VitalsAssessor()
        feed(&b, v, from: 0, to: 15)
        _ = b.assess(Vitals(cpu: 0.55), now: at(16))
        #expect(!feed(&b, v, from: 17, to: 35).contains(.sweating))
        #expect(b.assess(v, now: at(37)).contains(.sweating))
    }

    @Test func sweatingLeavesAfterTenSecondsBelow50() {
        var a = VitalsAssessor()
        feed(&a, Vitals(cpu: 0.7), from: 0, to: 25)
        #expect(a.conditions.contains(.sweating))
        let low = Vitals(cpu: 0.4)
        #expect(feed(&a, low, from: 26, to: 35).contains(.sweating))
        #expect(!a.assess(low, now: at(36)).contains(.sweating))
    }

    @Test func hotEntersAfterSixtySecondsAbove85OrThermalSerious() {
        var a = VitalsAssessor()
        let v = Vitals(cpu: 0.9)
        #expect(!feed(&a, v, from: 0, to: 59).contains(.hot))
        #expect(a.assess(v, now: at(60)).contains(.hot))
        var b = VitalsAssessor()
        let r = b.assess(Vitals(cpu: 0.1, thermal: .serious), now: at(0))
        #expect(r.contains(.hot) && r.contains(.sweating))
    }

    @Test func hotLeavesAfterFifteenSecondsBelow70() {
        var a = VitalsAssessor()
        feed(&a, Vitals(cpu: 0.9), from: 0, to: 60)
        #expect(a.conditions.contains(.hot))
        let mid = Vitals(cpu: 0.65)
        #expect(feed(&a, mid, from: 61, to: 75).contains(.hot))
        #expect(!a.assess(mid, now: at(76)).contains(.hot))
        // thermal serious blocks leaving
        var b = VitalsAssessor()
        feed(&b, Vitals(cpu: 0.9), from: 0, to: 60)
        #expect(feed(&b, Vitals(cpu: 0.2, thermal: .serious), from: 61, to: 100).contains(.hot))
        feed(&b, Vitals(cpu: 0.2), from: 101, to: 115)
        #expect(b.conditions.contains(.hot))
        #expect(!b.assess(Vitals(cpu: 0.2), now: at(116)).contains(.hot))
    }

    @Test func overheatedFollowsThermalCritical() {
        var a = VitalsAssessor()
        let r = a.assess(Vitals(thermal: .critical), now: at(0))
        #expect(r.contains(.overheated) && r.contains(.hot) && r.contains(.sweating))
        #expect(!a.assess(Vitals(thermal: .serious), now: at(1)).contains(.overheated))
    }

    @Test func stuffedFollowsPressureWarning() {
        var a = VitalsAssessor()
        #expect(a.assess(Vitals(memoryPressure: .warning), now: at(0)).contains(.stuffed))
        #expect(!a.assess(Vitals(memoryPressure: .normal), now: at(1)).contains(.stuffed))
    }

    @Test func dizzyOnCriticalOrSwapOver4GiB() {
        var a = VitalsAssessor()
        #expect(a.assess(Vitals(memoryPressure: .critical), now: at(0)).contains(.dizzy))
        #expect(!a.assess(Vitals(), now: at(1)).contains(.dizzy))
        // swap alone, with normal pressure, is not enough
        #expect(!a.assess(Vitals(swapUsed: 5 * Self.gib), now: at(2)).contains(.dizzy))
        // swap over 4 GiB needs pressure at warning or above
        #expect(!a.assess(Vitals(swapUsed: 4 * Self.gib, memoryPressure: .warning), now: at(3)).contains(.dizzy))
        #expect(a.assess(Vitals(swapUsed: 4 * Self.gib + 1, memoryPressure: .warning), now: at(4)).contains(.dizzy))
        #expect(a.assess(Vitals(swapUsed: 5 * Self.gib, memoryPressure: .warning), now: at(5)).contains(.dizzy))
        // under warning it leaves only below 3 GiB
        #expect(a.assess(Vitals(swapUsed: 3 * Self.gib, memoryPressure: .warning), now: at(6)).contains(.dizzy))
        #expect(!a.assess(Vitals(swapUsed: 3 * Self.gib - 1, memoryPressure: .warning), now: at(7)).contains(.dizzy))
        // it leaves when pressure returns to normal even with swap high
        #expect(a.assess(Vitals(swapUsed: 5 * Self.gib, memoryPressure: .warning), now: at(8)).contains(.dizzy))
        #expect(!a.assess(Vitals(swapUsed: 5 * Self.gib, memoryPressure: .normal), now: at(9)).contains(.dizzy))
        // pressure critical holds it even with no swap
        #expect(a.assess(Vitals(swapUsed: 0, memoryPressure: .critical), now: at(10)).contains(.dizzy))
        #expect(!a.assess(Vitals(swapUsed: 0, memoryPressure: .warning), now: at(11)).contains(.dizzy))
    }

    @Test func sleepyAndCryingFromBattery() {
        var a = VitalsAssessor()
        #expect(!a.assess(Vitals(batteryLevel: 20), now: at(0)).contains(.sleepy))
        #expect(a.assess(Vitals(batteryLevel: 19), now: at(1)).contains(.sleepy))
        #expect(a.assess(Vitals(batteryLevel: 24), now: at(2)).contains(.sleepy))
        #expect(!a.assess(Vitals(batteryLevel: 25), now: at(3)).contains(.sleepy))
        let r = a.assess(Vitals(batteryLevel: 9), now: at(4))
        #expect(r.contains(.crying) && r.contains(.sleepy))
        let r2 = a.assess(Vitals(batteryLevel: 14), now: at(5))
        #expect(r2.contains(.crying) && r2.contains(.sleepy))
        let r3 = a.assess(Vitals(batteryLevel: 15), now: at(6))
        #expect(!r3.contains(.crying) && r3.contains(.sleepy))
        let r4 = a.assess(Vitals(batteryLevel: 5, isCharging: true), now: at(7))
        #expect(!r4.contains(.crying) && !r4.contains(.sleepy))
        #expect(a.assess(Vitals(batteryLevel: 5, isCharging: false), now: at(8)).contains(.crying))
    }

    @Test func desktopNeverSleeps() {
        var a = VitalsAssessor()
        let r = a.assess(Vitals(batteryLevel: nil, isCharging: false), now: at(0))
        #expect(!r.contains(.sleepy) && !r.contains(.crying))
    }

    @Test func implicationsHold() {
        #expect(VitalsConditions.implied(.hot) == [.hot, .sweating])
        #expect(VitalsConditions.implied(.overheated) == [.overheated, .hot, .sweating])
        #expect(VitalsConditions.implied(.crying) == [.crying, .sleepy])
        #expect(VitalsConditions.implied([.stuffed, .dizzy]) == [.stuffed, .dizzy])
        #expect(VitalsConditions.implied([]) == [])
    }

    @Test func noFlickerInsideHysteresisBand() {
        var a = VitalsAssessor()
        feed(&a, Vitals(cpu: 0.7), from: 0, to: 25)
        #expect(a.conditions.contains(.sweating))
        // 0.50...0.60 for a long time keeps it on
        #expect(feed(&a, Vitals(cpu: 0.55), from: 26, to: 200).contains(.sweating))
        // and starting inside the band never enters
        var b = VitalsAssessor()
        #expect(!feed(&b, Vitals(cpu: 0.55), from: 0, to: 200).contains(.sweating))
        // hot band 0.70...0.85
        var c = VitalsAssessor()
        feed(&c, Vitals(cpu: 0.9), from: 0, to: 60)
        #expect(feed(&c, Vitals(cpu: 0.78), from: 61, to: 300).contains(.hot))
        var d = VitalsAssessor()
        #expect(!feed(&d, Vitals(cpu: 0.78), from: 0, to: 300).contains(.hot))
    }

    @Test func assessorResetTimersClearsPendingEntries() {
        var a = VitalsAssessor()
        let v = Vitals(cpu: 0.61)
        feed(&a, v, from: 0, to: 10)
        a.resetTimers()
        // 10 s before the reset do not count: 15 more seconds is not enough
        #expect(!feed(&a, v, from: 11, to: 25).contains(.sweating))
        #expect(!feed(&a, v, from: 26, to: 30).contains(.sweating))
        // the full 20 s again from the first sample after the reset
        #expect(a.assess(v, now: at(31)).contains(.sweating))
        // a held condition stays held through a reset
        a.resetTimers()
        #expect(a.assess(Vitals(cpu: 0.4), now: at(32)).contains(.sweating))
    }

    @Test func rawCpuIsIgnored() {
        var a = VitalsAssessor()
        #expect(!feed(&a, Vitals(cpu: 0.1, cpuRaw: 1.0), from: 0, to: 100).contains(.sweating))
    }
}
