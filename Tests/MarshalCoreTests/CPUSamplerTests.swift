import Testing
import Foundation
@testable import MarshalCore

struct CPUSamplerTests {
    @Test func loadIsBusyDeltaOverTotalDelta() {
        let a = CPUTicks(busy: 100, total: 1_000)
        let b = CPUTicks(busy: 400, total: 2_000)
        #expect(CPUSampler.load(previous: a, current: b) == 0.3)
    }

    @Test func loadClampsAndSurvivesZeroDelta() {
        let a = CPUTicks(busy: 100, total: 1_000)
        // zero total delta
        #expect(CPUSampler.load(previous: a, current: a) == 0)
        // counters went backwards (negative delta)
        #expect(CPUSampler.load(previous: a, current: CPUTicks(busy: 50, total: 900)) == 0)
        // busy moved more than total: clamped to 1
        #expect(CPUSampler.load(previous: a, current: CPUTicks(busy: 400, total: 1_100)) == 1)
        // busy went backwards while total advanced: clamped to 0
        #expect(CPUSampler.load(previous: a, current: CPUTicks(busy: 90, total: 1_100)) == 0)
    }

    @Test func ticksReadsTheMachine() {
        let t = CPUSampler.ticks()
        #expect(t != nil)
        if let t { #expect(t.total >= t.busy && t.total > 0) }
    }

    @Test func movingAverageWindowFive() {
        var m = MovingAverage(window: 5)
        #expect(m.push(1.0) == 1.0)
        #expect(m.push(0.0) == 0.5)
        _ = m.push(1.0); _ = m.push(0.0)
        #expect(m.push(1.0) == 0.6)            // [1,0,1,0,1]
        #expect(m.push(1.0) == 0.6)            // [0,1,0,1,1]: oldest 1 dropped
        #expect(abs(m.push(1.0) - 0.8) < 1e-12) // [1,0,1,1,1]
    }

    @Test func topPicksTheMaxDeltaAsAFractionOfTheInterval() {
        let previous: [Int32: UInt64] = [1: 1_000, 2: 5_000_000_000, 3: 0, 9: 7]
        let current: [Int32: UInt64] = [
            1: 1_000 + 2_000_000_000,     // 2 s of CPU over 10 s = 0.2
            2: 5_000_000_000 + 15_000_000_000, // 15 s over 10 s = 1.5 (multi-core)
            3: 500_000_000,
            4: 99_000_000_000              // new pid, no baseline: skipped
        ]
        let t = TopProcessSampler.top(previous: previous, current: current, interval: 10,
                                      name: { "p\($0)" })
        #expect(t == TopProcess(name: "p2", cpu: 1.5))
        let small = TopProcessSampler.top(previous: [1: 0], current: [1: 2_000_000_000], interval: 10,
                                          name: { _ in "x" })
        #expect(small == TopProcess(name: "x", cpu: 0.2))
    }

    @Test func topIsNilWithoutAnyProgressAndFallsBackToPid() {
        #expect(TopProcessSampler.top(previous: [1: 5], current: [1: 5], interval: 10) == nil)
        #expect(TopProcessSampler.top(previous: [1: 5], current: [1: 9], interval: 0) == nil)
        // pid reuse: counter went backwards, skipped
        #expect(TopProcessSampler.top(previous: [1: 50], current: [1: 9], interval: 10) == nil)
        let t = TopProcessSampler.top(previous: [77: 0], current: [77: 1_000_000_000], interval: 1,
                                      name: { _ in nil })
        #expect(t == TopProcess(name: "pid 77", cpu: 1))
    }

    @Test func snapshotSeesThisProcess() {
        let s = TopProcessSampler.snapshot()
        #expect(s[getpid()] != nil)
    }
}
