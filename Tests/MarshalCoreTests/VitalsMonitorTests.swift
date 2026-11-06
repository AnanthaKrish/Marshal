import Testing
import Foundation
@testable import MarshalCore

@MainActor
struct VitalsMonitorTests {
    static let t0 = Date(timeIntervalSince1970: 2_000_000)

    @Test func ingestDrivesConditions() {
        let m = VitalsMonitor()
        let hot = Vitals(cpu: 0.95, thermal: .serious)
        m.ingest(hot, now: Self.t0)
        #expect(m.vitals == hot)
        #expect(m.conditions == [.sweating, .hot])
        m.ingest(Vitals(memoryPressure: .warning, batteryLevel: 50), now: Self.t0.addingTimeInterval(1))
        #expect(m.conditions.contains(.stuffed))
    }

    @Test func overrideWinsUntilCleared() {
        let m = VitalsMonitor()
        m.ingest(Vitals(memoryPressure: .warning), now: Self.t0)
        #expect(m.conditions == [.stuffed])
        m.override = VitalsConditions.implied([.overheated])
        #expect(m.conditions == [.sweating, .hot, .overheated])
        // fresh samples do not displace the override
        m.ingest(Vitals(memoryPressure: .critical), now: Self.t0.addingTimeInterval(5))
        #expect(m.conditions == [.sweating, .hot, .overheated])
        m.override = nil
        #expect(m.conditions == [.dizzy])
    }

    @Test func pressureEventIsRetainedUntilSampled() {
        let m = VitalsMonitor()
        m.pressure.latest = .warning      // event arrives between samples
        #expect(m.conditions.isEmpty)
        // the next sample reads the retained level, and reading does not reset it
        m.ingest(Vitals(memoryPressure: m.pressure.latest), now: Self.t0)
        #expect(m.conditions.contains(.stuffed))
        #expect(m.pressure.latest == .warning)
    }

    @Test func topProcessFollowsRealLoadNotTheDemo() {
        let m = VitalsMonitor()
        m.override = VitalsConditions.implied(.sweating)
        #expect(!m.wantsTopProcess)  // a Sweating demo samples no processes
        m.override = VitalsConditions.implied(.sleepy)
        m.ingest(Vitals(cpu: 0.95, thermal: .serious), now: Self.t0)
        #expect(m.wantsTopProcess)   // real load under a Sleepy demo still does
    }

    @Test func samplingResetsAfterASleepGap() {
        var s = VitalsSampling()
        let gaps: [(TimeInterval, Bool)] = [
            (0, false), (1, false),
            (31, false),  // exactly 30 s is not a gap
            (62, true), (63, false),
        ]
        for (offset, expected) in gaps {
            let reset = s.resetAfterGap(now: Self.t0.addingTimeInterval(offset))
            #expect(reset == expected, "at +\(offset) s")
        }
    }

    @Test func startIsIdempotentAndSamplesTheMachine() async throws {
        let m = VitalsMonitor()
        m.start()
        m.start()
        try await Task.sleep(for: .milliseconds(2_500))
        m.stop()
        let v = m.vitals
        print("VitalsMonitor sample:", v)
        #expect(v.memoryTotal > 0)
        #expect(v.memoryUsed > 0)
        #expect((0...1).contains(v.cpu) && (0...1).contains(v.cpuRaw))
        let after = m.vitals
        try await Task.sleep(for: .milliseconds(2_200))
        #expect(m.vitals == after) // stop() cancelled sampling
    }
}
