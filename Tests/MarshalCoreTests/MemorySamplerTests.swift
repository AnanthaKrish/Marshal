import Testing
import Foundation
@testable import MarshalCore

struct MemorySamplerTests {
    @Test func usedIsActivePlusWiredPlusCompressedTimesPageSize() {
        #expect(MemorySampler.used(active: 10, wired: 5, compressed: 1, pageSize: 16_384) == 16 * 16_384)
        #expect(MemorySampler.used(active: 0, wired: 0, compressed: 0, pageSize: 4_096) == 0)
    }

    @Test func sampleReadsTheMachine() {
        let s = MemorySampler.sample()
        #expect(s != nil)
        if let s { #expect(s.total > 0 && s.used > 0 && s.used <= s.total) }
        #expect(MemorySampler.swapUsed() != nil)
    }

    @Test func pressureWatcherStartsAndStops() {
        let w = MemoryPressureWatcher()
        #expect(w.latest == .normal)
        w.start()
        w.start() // idempotent
        w.latest = .critical
        #expect(w.latest == .critical)
        w.stop()
        w.stop()
    }
}
